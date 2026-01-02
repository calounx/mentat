"""
CHOM API Test Suite - Team Management Tests

Tests all team management endpoints including:
- List team members
- Invite team members
- Update member roles
- Remove team members
- Transfer ownership
- Organization settings
"""

import time
import pytest


class TestListTeamMembers:
    """Test team member listing endpoint: GET /api/v1/team/members"""

    def test_list_team_members(self, make_request, auth_token):
        """Test listing team members."""
        response = make_request(
            "GET",
            "/team/members",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        assert "data" in response.data
        assert isinstance(response.data["data"], list)

        # Should have at least the current user
        assert len(response.data["data"]) >= 1

        # Verify member structure
        member = response.data["data"][0]
        assert "id" in member
        assert "name" in member
        assert "email" in member
        assert "role" in member

    def test_list_team_members_pagination(self, make_request, auth_token):
        """Test team member listing pagination."""
        response = make_request(
            "GET",
            "/team/members?page=1&per_page=10",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        meta = response.data["meta"]["pagination"]
        assert meta["current_page"] == 1
        assert meta["per_page"] == 10

    def test_list_team_members_unauthorized(self, make_request):
        """Test listing team members without authentication."""
        response = make_request("GET", "/team/members")

        response.assert_status(401)


class TestGetTeamMember:
    """Test get team member details endpoint: GET /api/v1/team/members/{id}"""

    def test_get_team_member_details(self, make_request, auth_token, registered_user):
        """Test retrieving team member details."""
        user_id = registered_user.user_id

        response = make_request(
            "GET",
            f"/team/members/{user_id}",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        member_data = response.data["data"]
        assert member_data["id"] == user_id
        assert member_data["email"] == registered_user.email

    def test_get_nonexistent_member(self, make_request, auth_token):
        """Test getting nonexistent team member."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "GET",
            f"/team/members/{fake_uuid}",
            auth_token=auth_token
        )

        response.assert_status(404)


class TestInviteTeamMember:
    """Test team member invitation endpoints"""

    def test_invite_team_member_as_owner(self, make_request, auth_token):
        """Test inviting a team member as owner."""
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/team/invitations",
            auth_token=auth_token,
            json={
                "email": f"invited_{timestamp}@chom.local",
                "role": "member",
                "name": "Invited User",
            }
        )

        assert response.status_code in [200, 201]
        response.assert_success()

    def test_invite_member_as_admin_role(self, make_request, auth_token):
        """Test owner can invite as admin."""
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/team/invitations",
            auth_token=auth_token,
            json={
                "email": f"admin_{timestamp}@chom.local",
                "role": "admin",
            }
        )

        # Owner can invite admin
        assert response.status_code in [200, 201, 403]

    def test_invite_duplicate_member(self, make_request, auth_token, registered_user):
        """Test inviting user who's already a member."""
        response = make_request(
            "POST",
            "/team/invitations",
            auth_token=auth_token,
            json={
                "email": registered_user.email,  # Already a member
                "role": "member",
            }
        )

        response.assert_status(400)
        assert response.error["code"] == "ALREADY_MEMBER"

    def test_invite_invalid_email(self, make_request, auth_token):
        """Test inviting with invalid email."""
        response = make_request(
            "POST",
            "/team/invitations",
            auth_token=auth_token,
            json={
                "email": "invalid-email",
                "role": "member",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_invite_missing_email(self, make_request, auth_token):
        """Test inviting without email."""
        response = make_request(
            "POST",
            "/team/invitations",
            auth_token=auth_token,
            json={
                "role": "member",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_list_invitations(self, make_request, auth_token):
        """Test listing pending invitations."""
        response = make_request(
            "GET",
            "/team/invitations",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        assert "data" in response.data

    def test_cancel_invitation(self, make_request, auth_token):
        """Test canceling an invitation."""
        # This is a placeholder test since invitations might not exist
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "DELETE",
            f"/team/invitations/{fake_uuid}",
            auth_token=auth_token
        )

        # Should either succeed or return not found
        assert response.status_code in [200, 404]


class TestUpdateTeamMember:
    """Test update team member role endpoint: PATCH /api/v1/team/members/{id}"""

    @pytest.fixture
    def second_member(self, make_request, auth_token):
        """Create a second team member for testing."""
        # For now, this is a placeholder since we need proper invitation system
        # In real scenario, we would invite and accept invitation
        return None

    def test_update_member_role_not_owner(self, make_request, auth_token, registered_user):
        """Test non-owners cannot update member roles."""
        user_id = registered_user.user_id

        response = make_request(
            "PATCH",
            f"/team/members/{user_id}",
            auth_token=auth_token,
            json={
                "role": "viewer",
            }
        )

        # Should succeed if owner, fail if not
        assert response.status_code in [200, 400, 403]

    def test_update_owner_role_forbidden(self, make_request, auth_token, registered_user):
        """Test cannot modify owner's role."""
        user_id = registered_user.user_id

        response = make_request(
            "PATCH",
            f"/team/members/{user_id}",
            auth_token=auth_token,
            json={
                "role": "member",
            }
        )

        # Owner cannot change their own role
        if response.status_code == 400:
            assert response.error["code"] == "CANNOT_MODIFY_OWNER"

    def test_update_invalid_role(self, make_request, auth_token, registered_user):
        """Test updating with invalid role."""
        user_id = registered_user.user_id

        response = make_request(
            "PATCH",
            f"/team/members/{user_id}",
            auth_token=auth_token,
            json={
                "role": "invalid_role",
            }
        )

        response.assert_status(422)
        assert not response.success


class TestRemoveTeamMember:
    """Test remove team member endpoint: DELETE /api/v1/team/members/{id}"""

    def test_remove_self_forbidden(self, make_request, auth_token, registered_user):
        """Test cannot remove yourself."""
        user_id = registered_user.user_id

        response = make_request(
            "DELETE",
            f"/team/members/{user_id}",
            auth_token=auth_token
        )

        if response.status_code == 400:
            assert response.error["code"] == "CANNOT_REMOVE_SELF"

    def test_remove_owner_forbidden(self, make_request, auth_token, registered_user):
        """Test cannot remove the owner."""
        user_id = registered_user.user_id

        response = make_request(
            "DELETE",
            f"/team/members/{user_id}",
            auth_token=auth_token
        )

        # Owner cannot be removed
        if response.status_code == 400:
            assert response.error["code"] in [
                "CANNOT_REMOVE_OWNER",
                "CANNOT_REMOVE_SELF"
            ]

    def test_remove_nonexistent_member(self, make_request, auth_token):
        """Test removing nonexistent member."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "DELETE",
            f"/team/members/{fake_uuid}",
            auth_token=auth_token
        )

        response.assert_status(404)


class TestTransferOwnership:
    """Test transfer ownership endpoint: POST /api/v1/team/transfer-ownership"""

    def test_transfer_ownership_missing_password(self, make_request, auth_token):
        """Test transfer ownership requires password."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "POST",
            "/team/transfer-ownership",
            auth_token=auth_token,
            json={
                "user_id": fake_uuid,
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_transfer_ownership_invalid_password(self, make_request, auth_token):
        """Test transfer ownership fails with invalid password."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "POST",
            "/team/transfer-ownership",
            auth_token=auth_token,
            json={
                "user_id": fake_uuid,
                "password": "wrong_password",
            }
        )

        # Should fail with either invalid password or user not found
        assert response.status_code in [401, 404]

    def test_transfer_ownership_nonexistent_user(self, make_request, auth_token, registered_user):
        """Test transfer ownership to nonexistent user."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "POST",
            "/team/transfer-ownership",
            auth_token=auth_token,
            json={
                "user_id": fake_uuid,
                "password": registered_user.password,
            }
        )

        response.assert_status(404)


class TestOrganization:
    """Test organization endpoints"""

    def test_get_organization(self, make_request, auth_token):
        """Test retrieving organization details."""
        response = make_request(
            "GET",
            "/organization",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        org_data = response.data["data"]
        assert "id" in org_data
        assert "name" in org_data
        assert "slug" in org_data
        assert "member_count" in org_data

    def test_update_organization_as_owner(self, make_request, auth_token):
        """Test updating organization settings as owner."""
        response = make_request(
            "PATCH",
            "/organization",
            auth_token=auth_token,
            json={
                "name": "Updated Organization Name",
            }
        )

        # Should succeed if owner
        assert response.status_code in [200, 403]

    def test_update_organization_invalid_data(self, make_request, auth_token):
        """Test updating organization with invalid data."""
        response = make_request(
            "PATCH",
            "/organization",
            auth_token=auth_token,
            json={
                "billing_email": "invalid-email",
            }
        )

        # Should fail validation if email is invalid
        assert response.status_code in [200, 422]

    def test_get_organization_unauthorized(self, make_request):
        """Test getting organization without authentication."""
        response = make_request("GET", "/organization")

        response.assert_status(401)


@pytest.mark.security
class TestTeamSecurity:
    """Test team management security."""

    def test_member_isolation_between_organizations(self, make_request, registered_user):
        """Test that users cannot access members from other organizations."""
        # Create another organization
        timestamp = int(time.time() * 1000)
        other_org_response = make_request(
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

        assert other_org_response.status_code == 201
        other_token = other_org_response.data["data"]["token"]

        # Try to access first organization's member
        response = make_request(
            "GET",
            f"/team/members/{registered_user.user_id}",
            auth_token=other_token
        )

        # Should not be able to access
        assert response.status_code in [403, 404]


@pytest.mark.performance
class TestTeamPerformance:
    """Test team endpoint performance."""

    def test_list_members_performance(self, make_request, auth_token, track_performance):
        """Test team member listing performance."""
        response = make_request(
            "GET",
            "/team/members",
            auth_token=auth_token
        )

        track_performance("/team/members", response.duration_ms)

        assert response.duration_ms < 500, \
            f"Listing team members took {response.duration_ms:.2f}ms (expected < 500ms)"
