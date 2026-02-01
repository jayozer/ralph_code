"""Main FastMCP server for ClerkIQ Playwright MCP.

Per TDD section 4.2.1 - Creates a FastMCP server that:
1. Proxies all standard Playwright MCP tools
2. Adds Browserbase-specific tools for session management and download retrieval
"""

from fastmcp import FastMCP

from clerkiq_playwright_mcp.tools.browserbase import (
    browserbase_create_session,
    browserbase_configure_downloads,
    browserbase_get_downloads,
    browserbase_stop_session,
)

# Create the main server
mcp = FastMCP(name="ClerkIQ Playwright MCP")

# Proxy all Playwright MCP tools using as_proxy
# This forwards: playwright_navigate, playwright_click, etc.
playwright_proxy = FastMCP.as_proxy(
    {
        "mcpServers": {
            "playwright": {
                "command": "npx",
                "args": ["@playwright/mcp@latest", "--headless"],
                "transport": "stdio",
            }
        }
    },
    name="Playwright",
)

# Mount the Playwright proxy (all tools get "playwright_" prefix)
mcp.mount(playwright_proxy)

# Register custom Browserbase tools using mcp.tool() to wrap the functions
mcp.tool(browserbase_create_session)
mcp.tool(browserbase_configure_downloads)
mcp.tool(browserbase_get_downloads)
mcp.tool(browserbase_stop_session)

if __name__ == "__main__":
    mcp.run()
