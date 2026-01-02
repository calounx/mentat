"""
CHOM API Test Suite - Backup Management Tests

Tests all backup management endpoints including:
- List backups
- Create backups
- Get backup details
- Delete backups
- Download backups
- Restore from backups
"""

import time
import pytest


class TestListBackups:
    """Test backup listing endpoints"""

    def test_list_all_backups(self, make_request, auth_token):
        """Test listing all backups for tenant."""
        response = make_request(
            "GET",
            "/backups",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        assert "data" in response.data
        assert "meta" in response.data
        assert isinstance(response.data["data"], list)

    def test_list_backups_pagination(self, make_request, auth_token):
        """Test backup listing pagination."""
        response = make_request(
            "GET",
            "/backups?page=1&per_page=10",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        meta = response.data["meta"]["pagination"]
        assert meta["current_page"] == 1
        assert meta["per_page"] == 10

    def test_list_backups_filter_by_site(self, make_request, auth_token, created_site):
        """Test filtering backups by site ID."""
        site_id = created_site["id"]

        response = make_request(
            "GET",
            f"/backups?site_id={site_id}",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        # All backups should belong to the specified site
        for backup in response.data["data"]:
            assert backup.get("site_id") == site_id

    def test_list_backups_filter_by_type(self, make_request, auth_token):
        """Test filtering backups by type."""
        response = make_request(
            "GET",
            "/backups?type=full",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

    def test_list_site_backups(self, make_request, auth_token, created_site):
        """Test listing backups for a specific site."""
        site_id = created_site["id"]

        response = make_request(
            "GET",
            f"/sites/{site_id}/backups",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        assert isinstance(response.data["data"], list)

    def test_list_backups_unauthorized(self, make_request):
        """Test listing backups without authentication."""
        response = make_request("GET", "/backups")

        response.assert_status(401)


class TestCreateBackup:
    """Test backup creation endpoint: POST /api/v1/backups"""

    def test_create_full_backup(self, make_request, auth_token, created_site):
        """Test creating a full backup."""
        site_id = created_site["id"]

        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": site_id,
                "backup_type": "full",
                "retention_days": 30,
            }
        )

        assert response.status_code in [201, 202]
        response.assert_success()

        backup_data = response.data["data"]
        assert backup_data["site_id"] == site_id
        assert backup_data["backup_type"] == "full"

        # Cleanup
        backup_id = backup_data["id"]
        make_request("DELETE", f"/backups/{backup_id}", auth_token=auth_token)

    def test_create_database_backup(self, make_request, auth_token, created_site):
        """Test creating a database-only backup."""
        site_id = created_site["id"]

        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": site_id,
                "backup_type": "database",
            }
        )

        assert response.status_code in [201, 202]
        response.assert_success()

        # Cleanup
        backup_id = response.data["data"]["id"]
        make_request("DELETE", f"/backups/{backup_id}", auth_token=auth_token)

    def test_create_files_backup(self, make_request, auth_token, created_site):
        """Test creating a files-only backup."""
        site_id = created_site["id"]

        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": site_id,
                "backup_type": "files",
            }
        )

        assert response.status_code in [201, 202]
        response.assert_success()

        # Cleanup
        backup_id = response.data["data"]["id"]
        make_request("DELETE", f"/backups/{backup_id}", auth_token=auth_token)

    def test_create_backup_via_site_endpoint(self, make_request, auth_token, created_site):
        """Test creating backup via site-specific endpoint."""
        site_id = created_site["id"]

        response = make_request(
            "POST",
            f"/sites/{site_id}/backups",
            auth_token=auth_token,
            json={
                "backup_type": "full",
            }
        )

        assert response.status_code in [201, 202]
        response.assert_success()

        # Cleanup
        backup_id = response.data["data"]["id"]
        make_request("DELETE", f"/backups/{backup_id}", auth_token=auth_token)

    def test_create_backup_missing_site_id(self, make_request, auth_token):
        """Test backup creation fails without site_id."""
        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "backup_type": "full",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_create_backup_invalid_site_id(self, make_request, auth_token):
        """Test backup creation fails with invalid site_id."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": fake_uuid,
                "backup_type": "full",
            }
        )

        response.assert_status(404)

    def test_create_backup_invalid_type(self, make_request, auth_token, created_site):
        """Test backup creation fails with invalid backup type."""
        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": created_site["id"],
                "backup_type": "invalid_type",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_create_backup_invalid_retention(self, make_request, auth_token, created_site):
        """Test backup creation with invalid retention days."""
        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": created_site["id"],
                "backup_type": "full",
                "retention_days": 500,  # Too long
            }
        )

        response.assert_status(422)
        assert not response.success


class TestGetBackup:
    """Test get backup details endpoint: GET /api/v1/backups/{id}"""

    @pytest.fixture
    def created_backup(self, make_request, auth_token, created_site):
        """Create a backup for testing."""
        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": created_site["id"],
                "backup_type": "full",
            }
        )

        assert response.status_code in [201, 202]
        backup_data = response.data["data"]

        yield backup_data

        # Cleanup
        make_request(
            "DELETE",
            f"/backups/{backup_data['id']}",
            auth_token=auth_token
        )

    def test_get_backup_details(self, make_request, auth_token, created_backup):
        """Test retrieving backup details."""
        backup_id = created_backup["id"]

        response = make_request(
            "GET",
            f"/backups/{backup_id}",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        backup_data = response.data["data"]
        assert backup_data["id"] == backup_id
        assert "backup_type" in backup_data
        assert "size_bytes" in backup_data
        assert "is_ready" in backup_data

    def test_get_backup_nonexistent(self, make_request, auth_token):
        """Test getting nonexistent backup."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "GET",
            f"/backups/{fake_uuid}",
            auth_token=auth_token
        )

        response.assert_status(404)

    def test_get_backup_unauthorized(self, make_request, created_backup):
        """Test getting backup without authentication."""
        response = make_request(
            "GET",
            f"/backups/{created_backup['id']}"
        )

        response.assert_status(401)


class TestDeleteBackup:
    """Test delete backup endpoint: DELETE /api/v1/backups/{id}"""

    def test_delete_backup(self, make_request, auth_token, created_site):
        """Test deleting a backup."""
        # Create a backup to delete
        create_response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": created_site["id"],
                "backup_type": "full",
            }
        )

        assert create_response.status_code in [201, 202]
        backup_id = create_response.data["data"]["id"]

        # Delete the backup
        delete_response = make_request(
            "DELETE",
            f"/backups/{backup_id}",
            auth_token=auth_token
        )

        delete_response.assert_status(200).assert_success()

    def test_delete_nonexistent_backup(self, make_request, auth_token):
        """Test deleting nonexistent backup."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "DELETE",
            f"/backups/{fake_uuid}",
            auth_token=auth_token
        )

        response.assert_status(404)

    def test_delete_backup_unauthorized(self, make_request, created_backup):
        """Test deleting backup without authentication."""
        response = make_request(
            "DELETE",
            f"/backups/{created_backup['id']}"
        )

        response.assert_status(401)


class TestDownloadBackup:
    """Test backup download endpoint: GET /api/v1/backups/{id}/download"""

    def test_download_backup_pending(self, make_request, auth_token, created_backup):
        """Test downloading a backup that's not ready yet."""
        backup_id = created_backup["id"]

        response = make_request(
            "GET",
            f"/backups/{backup_id}/download",
            auth_token=auth_token
        )

        # Should either succeed with URL or fail with "not ready" error
        if response.status_code == 200:
            assert "download_url" in response.data["data"]
            assert "expires_at" in response.data["data"]
        elif response.status_code == 400:
            assert response.error["code"] == "BACKUP_NOT_READY"
        else:
            pytest.fail(f"Unexpected status code: {response.status_code}")

    def test_download_backup_unauthorized(self, make_request, created_backup):
        """Test downloading backup without authentication."""
        response = make_request(
            "GET",
            f"/backups/{created_backup['id']}/download"
        )

        response.assert_status(401)


class TestRestoreBackup:
    """Test backup restore endpoint: POST /api/v1/backups/{id}/restore"""

    def test_restore_backup_not_ready(self, make_request, auth_token, created_backup):
        """Test restoring a backup that's not ready yet."""
        backup_id = created_backup["id"]

        response = make_request(
            "POST",
            f"/backups/{backup_id}/restore",
            auth_token=auth_token
        )

        # Should either accept restore or fail with "not ready" error
        if response.status_code in [200, 202]:
            response.assert_success()
        elif response.status_code == 400:
            assert response.error["code"] in [
                "BACKUP_NOT_READY",
                "BACKUP_EXPIRED"
            ]
        else:
            pytest.fail(f"Unexpected status code: {response.status_code}")

    def test_restore_nonexistent_backup(self, make_request, auth_token):
        """Test restoring nonexistent backup."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "POST",
            f"/backups/{fake_uuid}/restore",
            auth_token=auth_token
        )

        response.assert_status(404)

    def test_restore_backup_unauthorized(self, make_request, created_backup):
        """Test restoring backup without authentication."""
        response = make_request(
            "POST",
            f"/backups/{created_backup['id']}/restore"
        )

        response.assert_status(401)


@pytest.mark.performance
class TestBackupPerformance:
    """Test backup endpoint performance."""

    def test_list_backups_performance(self, make_request, auth_token, track_performance):
        """Test backup listing performance."""
        response = make_request(
            "GET",
            "/backups",
            auth_token=auth_token
        )

        track_performance("/backups", response.duration_ms)

        assert response.duration_ms < 500, \
            f"Listing backups took {response.duration_ms:.2f}ms (expected < 500ms)"

    def test_create_backup_performance(self, make_request, auth_token, created_site, track_performance):
        """Test backup creation API response time (not actual backup)."""
        response = make_request(
            "POST",
            "/backups",
            auth_token=auth_token,
            json={
                "site_id": created_site["id"],
                "backup_type": "full",
            }
        )

        track_performance("/backups [POST]", response.duration_ms)

        # API should respond quickly (async operation)
        assert response.duration_ms < 1000, \
            f"Backup creation took {response.duration_ms:.2f}ms (expected < 1000ms)"

        # Cleanup
        if response.status_code in [201, 202]:
            backup_id = response.data["data"]["id"]
            make_request("DELETE", f"/backups/{backup_id}", auth_token=auth_token)


@pytest.mark.security
class TestBackupSecurity:
    """Test backup security and isolation."""

    def test_backup_isolation_between_users(self, make_request, registered_user, created_backup):
        """Test that users cannot access other users' backups."""
        # Create another user
        timestamp = int(time.time() * 1000)
        other_user_response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Other User",
                "email": f"other_{timestamp}@chom.local",
                "password": "SecurePassword123!@#",
                "password_confirmation": "SecurePassword123!@#",
                "organization_name": f"Other Org {timestamp}",
            }
        )

        assert other_user_response.status_code == 201
        other_token = other_user_response.data["data"]["token"]

        # Try to access first user's backup
        response = make_request(
            "GET",
            f"/backups/{created_backup['id']}",
            auth_token=other_token
        )

        # Should not be able to access
        assert response.status_code in [403, 404]
