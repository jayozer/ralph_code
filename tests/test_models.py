"""Tests for Pydantic models.

Per TDD section 14.3 - Verify Pydantic models work correctly with proper defaults and validation.
"""

import pytest
from pydantic import ValidationError

from clerkiq_playwright_mcp.models import BrowserbaseConfig, SessionInfo
from clerkiq_playwright_mcp.tools.browserbase import (
    BrowserbaseSession,
    DownloadedFile,
    DownloadsResult,
)


class TestModels:
    """Tests for all Pydantic models in the project."""

    # =========================================================================
    # BrowserbaseSession tests (from tools/browserbase.py)
    # =========================================================================

    def test_browserbase_session_required_fields(self):
        """Test BrowserbaseSession requires session_id and cdp_url."""
        session = BrowserbaseSession(
            session_id="test-session-123",
            cdp_url="wss://connect.browserbase.com/test",
        )
        assert session.session_id == "test-session-123"
        assert session.cdp_url == "wss://connect.browserbase.com/test"

    def test_browserbase_session_live_url_optional(self):
        """Test BrowserbaseSession.live_url defaults to None."""
        session = BrowserbaseSession(
            session_id="test-session",
            cdp_url="wss://connect.browserbase.com/test",
        )
        assert session.live_url is None

    def test_browserbase_session_with_live_url(self):
        """Test BrowserbaseSession can include live_url."""
        session = BrowserbaseSession(
            session_id="test-session",
            cdp_url="wss://connect.browserbase.com/test",
            live_url="https://live.browserbase.com/test",
        )
        assert session.live_url == "https://live.browserbase.com/test"

    def test_browserbase_session_missing_required_raises(self):
        """Test BrowserbaseSession raises ValidationError for missing required fields."""
        with pytest.raises(ValidationError):
            BrowserbaseSession(session_id="test")  # Missing cdp_url

        with pytest.raises(ValidationError):
            BrowserbaseSession(cdp_url="wss://test")  # Missing session_id

    # =========================================================================
    # DownloadedFile tests (from tools/browserbase.py)
    # =========================================================================

    def test_downloaded_file_required_fields(self):
        """Test DownloadedFile requires all fields."""
        file = DownloadedFile(
            filename="document.pdf",
            content_base64="JVBERi0xLjQ=",
            size_bytes=12345,
        )
        assert file.filename == "document.pdf"
        assert file.content_base64 == "JVBERi0xLjQ="
        assert file.size_bytes == 12345

    def test_downloaded_file_missing_field_raises(self):
        """Test DownloadedFile raises ValidationError for missing fields."""
        with pytest.raises(ValidationError):
            DownloadedFile(filename="test.pdf", content_base64="abc")  # Missing size_bytes

        with pytest.raises(ValidationError):
            DownloadedFile(filename="test.pdf", size_bytes=100)  # Missing content_base64

        with pytest.raises(ValidationError):
            DownloadedFile(content_base64="abc", size_bytes=100)  # Missing filename

    # =========================================================================
    # DownloadsResult tests (from tools/browserbase.py)
    # =========================================================================

    def test_downloads_result_defaults(self):
        """Test DownloadsResult default values."""
        result = DownloadsResult()
        assert result.files == []
        assert result.total_files == 0
        assert result.message == ""

    def test_downloads_result_with_files(self):
        """Test DownloadsResult with populated files list."""
        file1 = DownloadedFile(
            filename="doc1.pdf",
            content_base64="YWJj",
            size_bytes=100,
        )
        file2 = DownloadedFile(
            filename="doc2.pdf",
            content_base64="ZGVm",
            size_bytes=200,
        )
        result = DownloadsResult(
            files=[file1, file2],
            total_files=2,
            message="Successfully retrieved 2 file(s)",
        )
        assert len(result.files) == 2
        assert result.files[0].filename == "doc1.pdf"
        assert result.files[1].filename == "doc2.pdf"
        assert result.total_files == 2
        assert result.message == "Successfully retrieved 2 file(s)"

    def test_downloads_result_empty_with_message(self):
        """Test DownloadsResult with no files but a message."""
        result = DownloadsResult(
            files=[],
            total_files=0,
            message="No downloads found within 120 seconds",
        )
        assert result.files == []
        assert result.total_files == 0
        assert result.message == "No downloads found within 120 seconds"

    # =========================================================================
    # BrowserbaseConfig tests (from models/types.py)
    # =========================================================================

    def test_browserbase_config_required_fields(self):
        """Test BrowserbaseConfig requires api_key and project_id."""
        config = BrowserbaseConfig(
            api_key="test-api-key-123",
            project_id="test-project-456",
        )
        assert config.api_key == "test-api-key-123"
        assert config.project_id == "test-project-456"

    def test_browserbase_config_missing_field_raises(self):
        """Test BrowserbaseConfig raises ValidationError for missing fields."""
        with pytest.raises(ValidationError):
            BrowserbaseConfig(api_key="key")  # Missing project_id

        with pytest.raises(ValidationError):
            BrowserbaseConfig(project_id="proj")  # Missing api_key

    # =========================================================================
    # SessionInfo tests (from models/types.py)
    # =========================================================================

    def test_session_info_required_fields(self):
        """Test SessionInfo requires session_id and cdp_url."""
        info = SessionInfo(
            session_id="session-123",
            cdp_url="wss://connect.browserbase.com/session-123",
        )
        assert info.session_id == "session-123"
        assert info.cdp_url == "wss://connect.browserbase.com/session-123"

    def test_session_info_defaults(self):
        """Test SessionInfo default values for optional fields."""
        info = SessionInfo(
            session_id="session-123",
            cdp_url="wss://test",
        )
        assert info.is_configured is False
        assert info.download_count == 0

    def test_session_info_with_custom_values(self):
        """Test SessionInfo with non-default values."""
        info = SessionInfo(
            session_id="session-123",
            cdp_url="wss://test",
            is_configured=True,
            download_count=5,
        )
        assert info.is_configured is True
        assert info.download_count == 5

    def test_session_info_missing_required_raises(self):
        """Test SessionInfo raises ValidationError for missing required fields."""
        with pytest.raises(ValidationError):
            SessionInfo(session_id="test")  # Missing cdp_url

        with pytest.raises(ValidationError):
            SessionInfo(cdp_url="wss://test")  # Missing session_id
