FROM python:3.12.6-bookworm as base-image

RUN apt-get -qq update  \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y \
        curl \
        ca-certificates \
        gcc \
        git \
        graphviz \
        jq \
        unzip \
        rsync \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && apt-get autoremove -y \
    && apt-get clean \
    && \
    rm -rf \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/cache/apt/* \
        /var/tmp/*

ENV TZ="America/Toronto"


FROM base-image as build-image

ARG HYDROQC2MQTT_VERSION

WORKDIR /usr/src/app

COPY setup.cfg pyproject.toml /usr/src/app/
COPY hydroqc2mqtt /usr/src/app/hydroqc2mqtt

# See https://github.com/pypa/setuptools/issues/3269
ENV DEB_PYTHON_INSTALL_LAYOUT=deb_system

ENV DISTRIBUTION_NAME=HYDROQC2MQTT
ENV SETUPTOOLS_SCM_PRETEND_VERSION_FOR_HYDROQC2MQTT=${HYDROQC2MQTT_VERSION}
ENV UV_NO_CACHE=true

ENV VIRTUAL_ENV=/opt/venv
RUN python3.12 -m venv /opt/venv

RUN --mount=type=tmpfs,target=/root/.cargo \
    curl https://sh.rustup.rs -sSf | \
    RUSTUP_INIT_SKIP_PATH_CHECK=yes sh -s -- -y

ENV --mount=type=tmpfs,target=/root/.cargo \
    PATH="/root/.cargo/bin:${PATH}" 

RUN --mount=type=tmpfs,target=/root/.cargo \
    rustc --version

RUN if [ `dpkg --print-architecture` = "armhf" ]; then \
       printf "[global]\nextra-index-url=https://www.piwheels.org/simple\n" > /etc/pip.conf ; \
    fi

RUN --mount=type=tmpfs,target=/root/.cargo \
    . /opt/venv/bin/activate && \
    pip config set global.extra-index-url https://gitlab.com/api/v4/projects/32908244/packages/pypi/simple && \
    pip install --upgrade pip && \
    pip install --upgrade --no-cache-dir tox twine && \
    pip install --upgrade setuptools_scm && \
    pip install --no-cache-dir . && \
    rm -rf \
        /root/.cache \
        /root/.cargo \
        /tmp/*
        
# RUN . /opt/venv/bin/activate && \
#     pip install --no-cache-dir msgpack ujson


FROM python:3.12-slim-bookworm

COPY --from=build-image /opt/venv/pyvenv.cfg /opt/venv/pyvenv.cfg
COPY --from=build-image /opt/venv/lib /opt/venv/lib
COPY --from=build-image /opt/venv/bin /opt/venv/bin

RUN \
    adduser hq2m \
        --uid 568 \
        --group \
        --system \
        --disabled-password \
        --no-create-home

USER hq2m

ENV PATH="/opt/venv/bin:$PATH"
ENV TZ="America/Toronto" \
    MQTT_DISCOVERY_DATA_TOPIC="homeassistant" \
    MQTT_DATA_ROOT_TOPIC="hydroqc" \
    SYNC_FREQUENCY=600

CMD [ "/opt/venv/bin/hydroqc2mqtt" ]

