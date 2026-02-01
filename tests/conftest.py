"""Pytest fixtures for Browserbase tools testing.

Per TDD section 13.7 - Fixtures for mocking Browserbase API and websockets.
"""

import base64
import io
import zipfile
from typing import Any, AsyncIterator
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


@pytest.fixture(autouse=True)
def mock_env_vars(request: pytest.FixtureRequest, monkeypatch: pytest.MonkeyPatch) -> None:
    """Set test environment variables for unit tests only.

    Autouse fixture that sets BROWSERBASE_API_KEY and BROWSERBASE_PROJECT_ID
    to test values before each test runs, EXCEPT for integration tests which
    need real credentials.
    """
    # Skip mocking for integration tests - they use real credentials
    if "test_integration" in request.node.nodeid:
        return
    monkeypatch.setenv("BROWSERBASE_API_KEY", "test-api-key")
    monkeypatch.setenv("BROWSERBASE_PROJECT_ID", "test-project-id")


@pytest.fixture
def mock_browserbase_client() -> MagicMock:
    """Create a mock Browserbase client.

    Returns a MagicMock configured to simulate the Browserbase SDK client
    with sessions.create, sessions.update, and sessions.downloads.list methods.
    """
    client = MagicMock()

    # Mock session object returned by sessions.create
    mock_session = MagicMock()
    mock_session.id = "test-session-id"
    mock_session.connect_url = "wss://test.browserbase.com/connect"
    mock_session.live_url = "https://test.browserbase.com/live/test-session-id"
    client.sessions.create.return_value = mock_session

    # Mock sessions.update (returns None on success)
    client.sessions.update.return_value = None

    # Mock sessions.downloads.list (returns BinaryAPIResponse-like object)
    mock_downloads_response = MagicMock()
    # Default to empty ZIP response
    mock_downloads_response.read.return_value = b""
    client.sessions.downloads.list.return_value = mock_downloads_response

    return client


@pytest.fixture
def mock_session() -> MagicMock:
    """Create a mock Browserbase session object.

    Returns a MagicMock simulating the session object returned by sessions.create().
    """
    session = MagicMock()
    session.id = "test-session-id"
    session.connect_url = "wss://test.browserbase.com/connect"
    session.live_url = "https://test.browserbase.com/live/test-session-id"
    return session


@pytest.fixture
def mock_websocket() -> AsyncMock:
    """Create a mock websocket for CDP testing.

    Returns an AsyncMock configured to simulate websocket communication
    with send/recv methods for CDP commands.
    """
    ws = AsyncMock()

    # Default success response for CDP commands
    ws.recv.return_value = '{"id": 1, "result": {}}'

    return ws


@pytest.fixture
def sample_zip_with_pdf() -> bytes:
    """Create a test ZIP file containing a sample PDF.

    Returns bytes of a valid ZIP archive containing a test PDF file,
    useful for testing browserbase_get_downloads.
    """
    # Create a simple PDF-like content (not a valid PDF, but sufficient for testing)
    pdf_content = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF"

    # Create ZIP in memory
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("test-document.pdf", pdf_content)

    return zip_buffer.getvalue()


@pytest.fixture
def sample_zip_with_multiple_files() -> bytes:
    """Create a test ZIP file containing multiple files.

    Returns bytes of a valid ZIP archive containing multiple test files
    including a PDF and a text file, plus a hidden file that should be skipped.
    """
    # Create sample file contents
    pdf_content = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF"
    txt_content = b"This is a test text file content."

    # Create ZIP in memory
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("document.pdf", pdf_content)
        zf.writestr("readme.txt", txt_content)
        # Add a hidden file that should be filtered out
        zf.writestr(".hidden", b"hidden content")
        # Add a subdirectory (will be filtered as directory)
        zf.writestr("subdir/", b"")

    return zip_buffer.getvalue()


@pytest.fixture
def empty_zip() -> bytes:
    """Create an empty ZIP file.

    Returns bytes of a valid but empty ZIP archive for testing
    the empty downloads case.
    """
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        pass  # Create empty ZIP

    return zip_buffer.getvalue()
