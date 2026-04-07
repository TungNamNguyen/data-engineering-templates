"""Fetch data from a public API using the requests library."""

import requests


def fetch_random_users(count: int = 3) -> list[dict]:
    """Fetch random users from a public API."""
    response = requests.get(
        f"https://randomuser.me/api/?results={count}",
        timeout=10,
    )
    response.raise_for_status()

    users = []
    for user in response.json()["results"]:
        users.append({
            "name": f"{user['name']['first']} {user['name']['last']}",
            "email": user["email"],
            "country": user["location"]["country"],
        })

    print(f"Fetched {len(users)} users:")
    for u in users:
        print(f"  - {u['name']} ({u['email']}) from {u['country']}")

    return users
