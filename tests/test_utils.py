import pytest
from src.utils import (
    is_prime,
    is_leap_year,
    fibonacci_series,
    days_between_dates,
    factorial,
)


class TestPrimeFinder:
    @pytest.mark.parametrize(
        "value, expected",
        [
            (2, True),
            (3, True),
            (5, True),
            (7, True),
            (11, True),
            (1, False),
            (0, False),
            (-5, False),
            (4, False),
            (9, False),
            (15, False),
        ],
    )
    def test_is_prime(self, value, expected):
        assert is_prime(value) == expected


class TestLeapYearFinder:
    @pytest.mark.parametrize(
        "year, expected",
        [
            (2024, True),
            (2020, True),
            (2000, True),
            (1900, False),
            (2023, False),
            (2100, False),
        ],
    )
    def test_is_leap_year(self, year, expected):
        assert is_leap_year(year) == expected


class TestFibonacciSeries:
    def test_fibonacci_zero(self):
        assert fibonacci_series(0) == []

    def test_fibonacci_one(self):
        assert fibonacci_series(1) == [0]

    def test_fibonacci_two(self):
        assert fibonacci_series(2) == [0, 1]

    def test_fibonacci_five(self):
        assert fibonacci_series(5) == [0, 1, 1, 2, 3]

    def test_fibonacci_ten(self):
        assert fibonacci_series(10) == [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]

    def test_fibonacci_negative(self):
        with pytest.raises(ValueError, match="non-negative"):
            fibonacci_series(-1)


class TestDaysBetweenDates:
    def test_days_between_dates_same_day(self):
        assert days_between_dates("2025-01-01", "2025-01-01") == 0

    def test_days_between_dates_forward(self):
        assert days_between_dates("2025-01-01", "2025-01-10") == 9

    def test_days_between_dates_reverse(self):
        assert days_between_dates("2025-01-10", "2025-01-01") == 9

    def test_days_between_dates_leap_year(self):
        assert days_between_dates("2024-02-28", "2024-03-01") == 2


class TestFactorial:
    @pytest.mark.parametrize(
        "value, expected",
        [
            (0, 1),
            (1, 1),
            (3, 6),
            (5, 120),
            (7, 5040),
        ],
    )
    def test_factorial(self, value, expected):
        assert factorial(value) == expected

    def test_factorial_negative(self):
        with pytest.raises(ValueError, match="non-negative"):
            factorial(-2)
