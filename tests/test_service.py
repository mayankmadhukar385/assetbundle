import pytest
from unittest.mock import MagicMock

from src.service import UtilityService


@pytest.fixture
def mock_repository():
    return MagicMock()


@pytest.fixture
def mock_logger():
    return MagicMock()


@pytest.fixture
def utility_service(mock_repository, mock_logger):
    return UtilityService(repository=mock_repository, logger=mock_logger)


def test_process_number_prime(utility_service, mock_repository, mock_logger):
    result = utility_service.process_number(7)

    assert result == {
        "number": 7,
        "is_prime": True,
        "factorial": 5040,
    }

    mock_logger.info.assert_called_once_with("Processing number: 7")
    mock_repository.save_result.assert_called_once_with(result)


def test_process_number_non_prime(utility_service, mock_repository, mock_logger):
    result = utility_service.process_number(8)

    assert result["number"] == 8
    assert result["is_prime"] is False
    assert result["factorial"] == 40320

    mock_logger.info.assert_called_once_with("Processing number: 8")
    mock_repository.save_result.assert_called_once_with(result)


def test_process_year_leap(utility_service, mock_repository, mock_logger):
    result = utility_service.process_year(2024)

    assert result == {
        "year": 2024,
        "is_leap_year": True,
    }

    mock_logger.info.assert_called_once_with("Processing year: 2024")
    mock_repository.save_result.assert_called_once_with(result)


def test_process_year_non_leap(utility_service, mock_repository, mock_logger):
    result = utility_service.process_year(2023)

    assert result == {
        "year": 2023,
        "is_leap_year": False,
    }

    mock_logger.info.assert_called_once_with("Processing year: 2023")
    mock_repository.save_result.assert_called_once_with(result)


def test_process_fibonacci(utility_service, mock_repository, mock_logger):
    result = utility_service.process_fibonacci(5)

    assert result == {
        "count": 5,
        "series": [0, 1, 1, 2, 3],
    }

    mock_logger.info.assert_called_once_with("Generating fibonacci for: 5")
    mock_repository.save_result.assert_called_once_with(result)


def test_process_dates(utility_service, mock_repository, mock_logger):
    result = utility_service.process_dates("2024-01-01", "2024-01-10")

    assert result == {
        "start_date": "2024-01-01",
        "end_date": "2024-01-10",
        "days": 9,
    }

    mock_logger.info.assert_called_once_with(
        "Calculating days between 2024-01-01 and 2024-01-10"
    )
    mock_repository.save_result.assert_called_once_with(result)