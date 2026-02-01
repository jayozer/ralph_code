"""Unit tests for Browserbase tools.

Per TDD section 14.1 - Tests for browserbase_create_session, configure_downloads,
get_downloads, and stop_session.
"""

import pytest
from unittest.mock import patch, MagicMock


class TestBrowserbaseCreateSession:
    """Tests for browserbase_create_session function."""

    @pytest.mark.asyncio
    async def test_create_session_success(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test successful session creation returns session_id and cdp_url."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            result = await browserbase_create_session()

            assert result.session_id == "test-session-id"
            assert result.cdp_url == "wss://test.browserbase.com/connect"
            assert result.live_url == "https://test.browserbase.com/live/test-session-id"

            # Verify create was called with expected defaults
            mock_browserbase_client.sessions.create.assert_called_once()
            call_kwargs = mock_browserbase_client.sessions.create.call_args.kwargs
            assert call_kwargs["project_id"] == "test-project-id"
            assert call_kwargs["proxies"] is True
            assert call_kwargs["timeout"] == 1800
            assert call_kwargs["keep_alive"] is True

    @pytest.mark.asyncio
    async def test_create_session_custom_params(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test session creation with custom parameters (proxies=False, custom timeout)."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            result = await browserbase_create_session(
                proxies=False,
                solve_captchas=False,
                timeout_seconds=600,
            )

            assert result.session_id == "test-session-id"
            assert result.cdp_url == "wss://test.browserbase.com/connect"

            # Verify create was called with custom parameters
            mock_browserbase_client.sessions.create.assert_called_once()
            call_kwargs = mock_browserbase_client.sessions.create.call_args.kwargs
            assert call_kwargs["proxies"] is False
            assert call_kwargs["timeout"] == 600
            # Check browser_settings has solve_captchas=False
            # BrowserSettings is a TypedDict, so it's a dict
            browser_settings = call_kwargs["browser_settings"]
            assert browser_settings["solve_captchas"] is False

    @pytest.mark.asyncio
    async def test_create_session_missing_api_key(self) -> None:
        """Test ValueError is raised when BROWSERBASE_API_KEY is not set."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_API_KEY",
            None,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            with pytest.raises(ValueError, match="BROWSERBASE_API_KEY"):
                await browserbase_create_session()

    @pytest.mark.asyncio
    async def test_create_session_missing_project_id(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test ValueError is raised when BROWSERBASE_PROJECT_ID is not set."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            None,
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            with pytest.raises(ValueError, match="BROWSERBASE_PROJECT_ID"):
                await browserbase_create_session()
