from datetime import datetime


def is_prime(n: int) -> bool:
    """Return True if n is a prime number, else False."""
    if n <= 1:
        return False
    if n == 2:
        return True
    if n % 2 == 0:
        return False

    i = 3
    while i * i <= n:
        if n % i == 0:
            return False
        i += 2
    return True


def is_leap_year(year: int) -> bool:
    """Return True if the year is a leap year, else False."""
    return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


def fibonacci_series(n: int) -> list[int]:
    """Return first n numbers of Fibonacci series."""
    if n < 0:
        raise ValueError("n must be non-negative")
    if n == 0:
        return []
    if n == 1:
        return [0]

    series = [0, 1]
    while len(series) < n:
        series.append(series[-1] + series[-2])
    return series


def days_between_dates(start_date: str, end_date: str, fmt: str = "%Y-%m-%d") -> int:
    """Return absolute number of days between two dates."""
    d1 = datetime.strptime(start_date, fmt)
    d2 = datetime.strptime(end_date, fmt)
    return abs((d2 - d1).days)


def factorial(n: int) -> int:
    """Return factorial of n."""
    if n < 0:
        raise ValueError("n must be non-negative")
    if n in (0, 1):
        return 1

    result = 1
    for i in range(2, n + 1):
        result *= i
    return result