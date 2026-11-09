FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates git python3 shellcheck \
    && rm -rf /var/lib/apt/lists/* \
    && groupmod --new-name vscode ubuntu \
    && usermod --login vscode --home /home/vscode --move-home --shell /bin/bash ubuntu

USER vscode
