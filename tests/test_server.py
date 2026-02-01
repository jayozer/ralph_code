"""Unit tests for server configuration.

Per TDD section 14.2 - Tests verifying server setup and tool registration.
"""

import pytest


class TestServerSetup:
    """Tests for server configuration and tool registration."""

    def test_server_has_custom_tools(self) -> None:
        """Test that all 4 Browserbase tools are registered with the server."""
        from clerkiq_playwright_mcp.server import mcp

        # Get list of registered tool names
        # FastMCP stores tools in _tool_manager._tools dict
        registered_tools = list(mcp._tool_manager._tools.keys())

        # Verify all 4 Browserbase tools are registered
        expected_tools = [
            "browserbase_create_session",
            "browserbase_configure_downloads",
            "browserbase_get_downloads",
            "browserbase_stop_session",
        ]

        for tool_name in expected_tools:
            assert tool_name in registered_tools, (
                f"Tool '{tool_name}' not found in registered tools: {registered_tools}"
            )

    def test_server_name(self) -> None:
        """Test that server name is 'ClerkIQ Playwright MCP'."""
        from clerkiq_playwright_mcp.server import mcp

        assert mcp.name == "ClerkIQ Playwright MCP"
