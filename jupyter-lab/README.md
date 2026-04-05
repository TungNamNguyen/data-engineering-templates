# JupyterLab

A simple Docker Compose setup for JupyterLab.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

## Quick Start

1. Copy the environment file:

```bash
cp .env.example .env
```

2. Create the notebooks directory and start JupyterLab:

```bash
mkdir -p notebooks
docker compose up -d
```

3. Open in your browser:

```
http://localhost:8889?token=jupyter
```

> The default token is `jupyter`. You can change it in `.env` under `JUPYTER_TOKEN`.

## Stop

```bash
docker compose down
```

## Troubleshooting

### Permission denied on `notebooks/`

If you ran `docker compose up` without creating the `notebooks/` directory first, Docker creates it as root and you won't be able to write to it.

**Fix:**

```bash
docker compose down
sudo chown -R $USER:$USER notebooks
```

Or if you don't have sudo:

```bash
docker compose down
docker run --rm -v ./notebooks:/data alpine chown -R $(id -u):$(id -g) /data
```

Then start again:

```bash
docker compose up -d
```

## Included Libraries

The `jupyter/scipy-notebook` image comes with:

- pandas, numpy, scipy
- matplotlib, seaborn
- scikit-learn

To install additional packages, run inside a notebook cell:

```python
!pip install <package-name>
```

## Notes

- Notebooks are saved in the `./notebooks` directory.
- Port `8889` on your machine maps to port `8888` inside the container. Change `JUPYTER_PORT` in `.env` if it conflicts with another service.
