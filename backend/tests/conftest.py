import pytest

from backend.app import create_app


@pytest.fixture
def app(tmp_path):
    db_path = str(tmp_path / "test.db")
    return create_app(db_path=db_path, secret_key="test-secret")


@pytest.fixture
def client(app):
    return app.test_client()
