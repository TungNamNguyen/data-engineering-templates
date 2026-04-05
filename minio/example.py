"""
MinIO example — upload/download files in various formats (text, csv, parquet, json, delta, iceberg).

    pip install minio pandas pyarrow deltalake pyiceberg
    python example.py
"""

import io

import pandas as pd
from minio import Minio

ENDPOINT = "localhost:9000"
ACCESS_KEY = "minioadmin"
SECRET_KEY = "minioadmin"
BUCKET_NAME = "my-bucket"

# s3 storage options used by delta lake and iceberg
S3_OPTS = {
    "AWS_ENDPOINT_URL": f"http://{ENDPOINT}",
    "AWS_ACCESS_KEY_ID": ACCESS_KEY,
    "AWS_SECRET_ACCESS_KEY": SECRET_KEY,
    "AWS_ALLOW_HTTP": "true",
    "AWS_S3_ALLOW_UNSAFE_RENAME": "true",
    "AWS_REGION": "us-east-1",
}


# --- client / bucket --------------------------------------------------------

def get_client():
    return Minio(ENDPOINT, access_key=ACCESS_KEY, secret_key=SECRET_KEY, secure=False)


def create_bucket(client, bucket_name):
    if not client.bucket_exists(bucket_name):
        client.make_bucket(bucket_name)
        print(f"Bucket '{bucket_name}' created.")
    else:
        print(f"Bucket '{bucket_name}' already exists.")


# --- upload ------------------------------------------------------------------

def upload_text(client, bucket_name, key, text):
    data = text.encode("utf-8")
    client.put_object(bucket_name, key, io.BytesIO(data), len(data), content_type="text/plain")
    print(f"Uploaded text '{key}'.")


def upload_csv(client, bucket_name, key, df):
    data = df.to_csv(index=False).encode("utf-8")
    client.put_object(bucket_name, key, io.BytesIO(data), len(data), content_type="text/csv")
    print(f"Uploaded CSV '{key}'.")


def upload_parquet(client, bucket_name, key, df):
    buf = io.BytesIO()
    df.to_parquet(buf, index=False)
    buf.seek(0)
    client.put_object(bucket_name, key, buf, buf.getbuffer().nbytes, content_type="application/octet-stream")
    print(f"Uploaded parquet '{key}'.")


def upload_json(client, bucket_name, key, df):
    data = df.to_json(orient="records", indent=2).encode("utf-8")
    client.put_object(bucket_name, key, io.BytesIO(data), len(data), content_type="application/json")
    print(f"Uploaded JSON '{key}'.")


# --- delta lake --------------------------------------------------------------
# writes a delta table directly to minio via s3:// path (no minio client needed)

def write_delta(df, table_path):
    import pyarrow as pa
    from deltalake import write_deltalake
    table = pa.Table.from_pandas(df)
    write_deltalake(table_path, table, storage_options=S3_OPTS, mode="overwrite")
    print(f"Wrote delta table to '{table_path}'.")


def read_delta(table_path):
    from deltalake import DeltaTable
    dt = DeltaTable(table_path, storage_options=S3_OPTS)
    df = dt.to_pandas()
    print(f"Read delta table from '{table_path}':")
    print(df)
    return df


# --- iceberg -----------------------------------------------------------------
# uses pyiceberg with a sqlite catalog, storing data on minio via s3://

def get_iceberg_catalog():
    from pyiceberg.catalog.sql import SqlCatalog
    return SqlCatalog(
        "local",
        **{
            "uri": "sqlite:///iceberg_catalog.db",
            "s3.endpoint": f"http://{ENDPOINT}",
            "s3.access-key-id": ACCESS_KEY,
            "s3.secret-access-key": SECRET_KEY,
            "s3.region": "us-east-1",
        },
    )


def write_iceberg(df, catalog, namespace, table_name, bucket_name):
    import pyarrow as pa
    from pyiceberg.exceptions import NamespaceAlreadyExistsError, TableAlreadyExistsError

    try:
        catalog.create_namespace(namespace)
    except NamespaceAlreadyExistsError:
        pass

    full_name = f"{namespace}.{table_name}"
    arrow_table = pa.Table.from_pandas(df)

    try:
        catalog.create_table(
            full_name,
            schema=arrow_table.schema,
            location=f"s3://{bucket_name}/iceberg/{table_name}",
        )
    except TableAlreadyExistsError:
        pass

    iceberg_table = catalog.load_table(full_name)
    iceberg_table.overwrite(arrow_table)
    print(f"Wrote iceberg table '{full_name}'.")


def read_iceberg(catalog, namespace, table_name):
    full_name = f"{namespace}.{table_name}"
    table = catalog.load_table(full_name)
    df = table.scan().to_pandas()
    print(f"Read iceberg table '{full_name}':")
    print(df)
    return df


# --- download / list ---------------------------------------------------------

def list_objects(client, bucket_name):
    print(f"Objects in '{bucket_name}':")
    for obj in client.list_objects(bucket_name, recursive=True):
        print(f"  - {obj.object_name} ({obj.size} bytes)")


def download_text(client, bucket_name, key):
    response = client.get_object(bucket_name, key)
    try:
        content = response.read().decode("utf-8")
        print(f"Downloaded '{key}': {content}")
    finally:
        response.close()
        response.release_conn()


def download_parquet(client, bucket_name, key):
    response = client.get_object(bucket_name, key)
    try:
        df = pd.read_parquet(io.BytesIO(response.read()))
        print(f"Downloaded '{key}':")
        print(df)
        return df
    finally:
        response.close()
        response.release_conn()


# --- main --------------------------------------------------------------------

def main():
    client = get_client()

    df = pd.DataFrame({
        "id": [1, 2, 3],
        "name": ["alice", "bob", "charlie"],
        "score": [85.5, 92.0, 78.3],
    })

    create_bucket(client, BUCKET_NAME)

    # plain files via minio client
    upload_text(client, BUCKET_NAME, "hello.txt", "Hello from MinIO!")
    upload_csv(client, BUCKET_NAME, "data/sample.csv", df)
    upload_parquet(client, BUCKET_NAME, "data/sample.parquet", df)
    upload_json(client, BUCKET_NAME, "data/sample.json", df)

    # delta lake — writes directly to s3://
    write_delta(df, f"s3://{BUCKET_NAME}/delta/sample")
    read_delta(f"s3://{BUCKET_NAME}/delta/sample")

    # iceberg — uses a local sqlite catalog, data on s3://
    catalog = get_iceberg_catalog()
    write_iceberg(df, catalog, "default", "sample", BUCKET_NAME)
    read_iceberg(catalog, "default", "sample")

    # see everything that ended up in the bucket
    list_objects(client, BUCKET_NAME)

    # download examples
    download_text(client, BUCKET_NAME, "hello.txt")
    download_parquet(client, BUCKET_NAME, "data/sample.parquet")


if __name__ == "__main__":
    main()
