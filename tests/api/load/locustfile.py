"""
CHOM API Load Testing - Locust Configuration

This file defines load testing scenarios for the CHOM API.

Run with:
    locust -f tests/api/load/locustfile.py --host=http://localhost:8000

Web UI will be available at: http://localhost:8089
"""

import os
import random
import time
from locust import HttpUser, task, between, events
from dotenv import load_dotenv

# Load test environment
load_dotenv(".env.testing")

API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8000/api/v1")
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "load_test@chom.local")
TEST_USER_PASSWORD = os.getenv("TEST_USER_PASSWORD", "LoadTest123!@#")


class CHOMAPIUser(HttpUser):
    """
    Simulates a user interacting with the CHOM API.

    Each user will register, login, perform operations, and logout.
    """

    # Wait between 1-3 seconds between tasks
    wait_time = between(1, 3)

    # Store user-specific data
    auth_token = None
    user_id = None
    site_id = None
    sites = []

    def on_start(self):
        """Called when a simulated user starts."""
        self.register_and_login()

    def on_stop(self):
        """Called when a simulated user stops."""
        if self.auth_token:
            self.logout()

    def register_and_login(self):
        """Register a new user and login."""
        timestamp = int(time.time() * 1000)
        random_suffix = random.randint(1000, 9999)
        email = f"loadtest_{timestamp}_{random_suffix}@chom.local"

        # Register
        with self.client.post(
            "/api/v1/auth/register",
            json={
                "name": f"Load Test User {timestamp}",
                "email": email,
                "password": TEST_USER_PASSWORD,
                "password_confirmation": TEST_USER_PASSWORD,
                "organization_name": f"Load Test Org {timestamp}",
            },
            catch_response=True
        ) as response:
            if response.status_code == 201:
                data = response.json()
                self.auth_token = data["data"]["token"]
                self.user_id = data["data"]["user"]["id"]
                response.success()
            else:
                response.failure(f"Registration failed: {response.status_code}")

    def logout(self):
        """Logout the current user."""
        if self.auth_token:
            self.client.post(
                "/api/v1/auth/logout",
                headers={"Authorization": f"Bearer {self.auth_token}"}
            )

    @task(3)
    def get_current_user(self):
        """Get current user profile (common operation)."""
        if not self.auth_token:
            return

        with self.client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            name="/auth/me",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Failed to get user: {response.status_code}")

    @task(5)
    def list_sites(self):
        """List all sites (very common operation)."""
        if not self.auth_token:
            return

        with self.client.get(
            "/api/v1/sites",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            name="/sites",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                data = response.json()
                self.sites = data.get("data", [])
                response.success()
            else:
                response.failure(f"Failed to list sites: {response.status_code}")

    @task(2)
    def create_site(self):
        """Create a new site (moderate frequency)."""
        if not self.auth_token:
            return

        timestamp = int(time.time() * 1000)
        random_suffix = random.randint(1000, 9999)
        domain = f"load-{timestamp}-{random_suffix}.example.com"

        site_types = ["wordpress", "html", "laravel"]
        php_versions = ["8.2", "8.4"]

        with self.client.post(
            "/api/v1/sites",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            json={
                "domain": domain,
                "site_type": random.choice(site_types),
                "php_version": random.choice(php_versions),
                "ssl_enabled": True,
            },
            name="/sites [POST]",
            catch_response=True
        ) as response:
            if response.status_code in [201, 202]:
                data = response.json()
                site_id = data["data"]["id"]
                self.sites.append(data["data"])
                response.success()
            else:
                response.failure(f"Failed to create site: {response.status_code}")

    @task(3)
    def get_site_details(self):
        """Get details of a specific site."""
        if not self.auth_token or not self.sites:
            return

        site = random.choice(self.sites)
        site_id = site["id"]

        with self.client.get(
            f"/api/v1/sites/{site_id}",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            name="/sites/{id}",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Failed to get site: {response.status_code}")

    @task(1)
    def get_site_metrics(self):
        """Get site metrics (less frequent)."""
        if not self.auth_token or not self.sites:
            return

        site = random.choice(self.sites)
        site_id = site["id"]

        with self.client.get(
            f"/api/v1/sites/{site_id}/metrics",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            name="/sites/{id}/metrics",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Failed to get metrics: {response.status_code}")

    @task(2)
    def list_backups(self):
        """List all backups."""
        if not self.auth_token:
            return

        with self.client.get(
            "/api/v1/backups",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            name="/backups",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Failed to list backups: {response.status_code}")

    @task(1)
    def list_team_members(self):
        """List team members (less frequent)."""
        if not self.auth_token:
            return

        with self.client.get(
            "/api/v1/team/members",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            name="/team/members",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Failed to list team: {response.status_code}")

    @task(1)
    def get_organization(self):
        """Get organization details (less frequent)."""
        if not self.auth_token:
            return

        with self.client.get(
            "/api/v1/organization",
            headers={"Authorization": f"Bearer {self.auth_token}"},
            name="/organization",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Failed to get org: {response.status_code}")


class HealthCheckUser(HttpUser):
    """
    Simulates health check monitoring (unauthenticated).

    This represents automated monitoring systems.
    """

    wait_time = between(5, 10)

    @task
    def health_check(self):
        """Perform basic health check."""
        with self.client.get(
            "/api/v1/health",
            name="/health",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Health check failed: {response.status_code}")


# ============================================================================
# Event Handlers for Custom Reporting
# ============================================================================

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Called when load test starts."""
    print("\n" + "="*70)
    print("CHOM API Load Test Starting")
    print("="*70)
    print(f"Target: {environment.host}")
    print(f"Users: {environment.runner.target_user_count if hasattr(environment.runner, 'target_user_count') else 'N/A'}")
    print("="*70 + "\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Called when load test stops."""
    print("\n" + "="*70)
    print("CHOM API Load Test Complete")
    print("="*70)

    stats = environment.stats
    print(f"\nTotal Requests: {stats.total.num_requests}")
    print(f"Total Failures: {stats.total.num_failures}")
    print(f"Average Response Time: {stats.total.avg_response_time:.2f}ms")
    print(f"Min Response Time: {stats.total.min_response_time:.2f}ms")
    print(f"Max Response Time: {stats.total.max_response_time:.2f}ms")
    print(f"Requests/sec: {stats.total.total_rps:.2f}")

    if stats.total.num_requests > 0:
        failure_rate = (stats.total.num_failures / stats.total.num_requests) * 100
        print(f"Failure Rate: {failure_rate:.2f}%")

    print("="*70 + "\n")
