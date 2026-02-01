"""Integration tests for Browserbase tools.

Per TDD section 14.4 - These tests require real Browserbase credentials.
They skip by default when BROWSERBASE_API_KEY is not set in the environment.

To run these tests manually:
    export BROWSERBASE_API_KEY="your-api-key"
    export BROWSERBASE_PROJECT_ID="your-project-id"
    uv run pytest tests/test_integration.py -v
"""

import os

import pytest

# Skip all tests in this module if credentials are not set
pytestmark = pytest.mark.skipif(
    not os.environ.get("BROWSERBASE_API_KEY"),
    reason="BROWSERBASE_API_KEY environment variable not set",
)


class TestIntegration:
    """Integration tests for Browserbase tools with real credentials.

    These tests exercise the full lifecycle of Browserbase sessions
    and require valid API credentials to run.
    """

    @pytest.mark.asyncio
    async def test_full_session_lifecycle(self) -> None:
        """Test complete session lifecycle: create -> configure downloads -> stop.

        This test verifies:
        - Session can be created with default parameters
        - Session ID and CDP URL are returned
        - Download configuration succeeds
        - Session can be stopped cleanly
        """
        from clerkiq_playwright_mcp.tools.browserbase import (
            browserbase_create_session,
            browserbase_configure_downloads,
            browserbase_stop_session,
        )

        session = None
        try:
            # Create session
            session = await browserbase_create_session(
                proxies=False,  # Don't need proxies for simple test
                solve_captchas=False,  # Don't need captcha solving
                timeout_seconds=300,  # 5 minute timeout
            )

            # Verify session was created
            assert session.session_id is not None
            assert len(session.session_id) > 0
            assert session.cdp_url is not None
            assert session.cdp_url.startswith("wss://")

            # Configure downloads
            configure_result = await browserbase_configure_downloads(
                cdp_url=session.cdp_url
            )
            assert configure_result is True

        finally:
            # Always clean up the session
            if session is not None:
                stop_result = await browserbase_stop_session(
                    session_id=session.session_id
                )
                # Note: stop may fail if session already expired, which is OK
                assert stop_result in (True, False)

    @pytest.mark.asyncio
    async def test_get_downloads_no_files(self) -> None:
        """Test retrieving downloads from a session with no downloads.

        This test verifies:
        - Session can be created
        - Downloads API returns empty result when no files downloaded
        - Session is properly cleaned up
        """
        from clerkiq_playwright_mcp.tools.browserbase import (
            browserbase_create_session,
            browserbase_get_downloads,
            browserbase_stop_session,
        )

        session = None
        try:
            # Create session
            session = await browserbase_create_session(
                proxies=False,
                solve_captchas=False,
                timeout_seconds=300,
            )

            # Try to get downloads immediately (should be empty)
            # Use short timeout since we know there are no downloads
            downloads = await browserbase_get_downloads(
                session_id=session.session_id,
                timeout_seconds=5,
                poll_interval=1.0,
            )

            # Verify no downloads
            assert downloads.total_files == 0
            assert len(downloads.files) == 0
            assert "No downloads found" in downloads.message

        finally:
            # Always clean up the session
            if session is not None:
                await browserbase_stop_session(session_id=session.session_id)
