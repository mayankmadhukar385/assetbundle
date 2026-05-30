from src.utils import is_prime, is_leap_year, fibonacci_series, days_between_dates, factorial


class UtilityService:
    def __init__(self, repository, logger):
        self.repository = repository
        self.logger = logger

    def process_number(self, n: int) -> dict:
        self.logger.info(f"Processing number: {n}")

        result = {
            "number": n,
            "is_prime": is_prime(n),
            "factorial": factorial(n) if n >= 0 else None,
        }

        self.repository.save_result(result)
        return result

    def process_year(self, year: int) -> dict:
        self.logger.info(f"Processing year: {year}")

        result = {
            "year": year,
            "is_leap_year": is_leap_year(year),
        }

        self.repository.save_result(result)
        return result

    def process_fibonacci(self, n: int) -> dict:
        self.logger.info(f"Generating fibonacci for: {n}")

        result = {
            "count": n,
            "series": fibonacci_series(n),
        }

        self.repository.save_result(result)
        return result

    def process_dates(self, start_date: str, end_date: str) -> dict:
        self.logger.info(f"Calculating days between {start_date} and {end_date}")

        result = {
            "start_date": start_date,
            "end_date": end_date,
            "days": days_between_dates(start_date, end_date),
        }

        self.repository.save_result(result)
        return result