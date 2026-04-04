"""Example DAG — calls a script in src/ that uses an external library (requests)."""

from datetime import datetime, timedelta

from airflow.decorators import dag, task

from etl.extract import fetch_random_users


@dag(
    dag_id="example_dag",
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["example"],
    default_args={
        "owner": "airflow",
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
)
def example_dag():
    @task
    def fetch_users(count: int = 3):
        return fetch_random_users(count)

    fetch_users(count=3)


example_dag()
