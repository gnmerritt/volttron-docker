ARG image_user=amd64
ARG image_repo=debian
ARG image_tag=buster

FROM ${image_user}/${image_repo}:${image_tag} as volttron_base

SHELL [ "bash", "-c" ]

ENV OS_TYPE=debian
ENV DIST=buster
ENV VOLTTRON_GIT_BRANCH=releases/7.x
ENV VOLTTRON_USER_HOME=/home/volttron
ENV VOLTTRON_HOME=${VOLTTRON_USER_HOME}/.volttron
ENV CODE_ROOT=/code
ENV VOLTTRON_ROOT=${CODE_ROOT}/volttron
ENV VOLTTRON_USER=volttron
ENV RABBITMQ_VERSION=3.7.7
ENV RMQ_ROOT=${VOLTTRON_USER_HOME}/rabbitmq_server
ENV RMQ_HOME=${RMQ_ROOT}/rabbitmq_server-${RABBITMQ_VERSION}

USER root
RUN set -eux; apt-get update; apt-get install -y --no-install-recommends \
    procps \
    gosu \
    vim \
    tree \
    build-essential \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-psycopg2 \
    openssl \
    libssl-dev \
    libevent-dev \
    git \
    gnupg \
    dirmngr \
    apt-transport-https \
    wget \
    curl \
    ca-certificates \
    libffi-dev
# backwards compatibility for scripted pip invocations
RUN ln -s $(which pip3) /usr/bin/pip
RUN id -u $VOLTTRON_USER &>/dev/null || adduser --disabled-password --gecos "" $VOLTTRON_USER

RUN mkdir -p /code \
  && chown -R $VOLTTRON_USER.$VOLTTRON_USER /code \
  && echo "export PATH=/home/volttron/.local/bin:$PATH" > /home/volttron/.bashrc

############################################
# ENDING volttron_base image
############################################

FROM volttron_base AS volttron_core

# Note I couldn't get variable expansion on the chown argument to work here
# so must hard code the user.  Note this is a feature request for docker
# https://github.com/moby/moby/issues/35018
# COPY --chown=volttron:volttron . ${VOLTTRON_ROOT}

RUN git clone https://github.com/VOLTTRON/volttron -b ${VOLTTRON_GIT_BRANCH} ${VOLTTRON_ROOT} \
  && chown -R volttron.volttron ${VOLTTRON_ROOT}

USER $VOLTTRON_USER
WORKDIR ${VOLTTRON_ROOT}
# install the optional dependencies here, boostrap.py doesn't work in the container
# (except for postgresql, which uses the system package for better stability)
RUN pip3 install -e ${VOLTTRON_ROOT} --user \
  && pip3 install -e ${VOLTTRON_ROOT}[web] --user \
  && pip3 install -e ${VOLTTRON_ROOT}[pandas] --user \
  && pip3 install -e ${VOLTTRON_ROOT}[influxdb] --user \
  && pip3 install -e ${VOLTTRON_ROOT}[weather] --user \
  && pip3 install -e ${VOLTTRON_ROOT}[mongo] --user \
  && pip3 install -e ${VOLTTRON_ROOT}[market] --user \
  && pip3 install -e ${VOLTTRON_ROOT}[drivers] --user \
  && pip3 install -e ${VOLTTRON_ROOT}[crate] --user
RUN echo "packages installed at `date`"

############################################
# RABBITMQ SPECIFIC INSTALLATION
############################################
USER root
RUN ./scripts/rabbit_dependencies.sh $OS_TYPE $DIST

RUN mkdir /startup $VOLTTRON_HOME && \
    chown $VOLTTRON_USER.$VOLTTRON_USER $VOLTTRON_HOME
COPY ./core/entrypoint.sh /startup/entrypoint.sh
COPY ./core/bootstart.sh /startup/bootstart.sh
COPY ./core/setup-platform.py /startup/setup-platform.py
RUN chmod +x /startup/*

USER $VOLTTRON_USER
RUN mkdir $RMQ_ROOT
ENV RABBITMQ_TAR=rabbitmq-server-generic-unix-${RABBITMQ_VERSION}.tar.xz
RUN set -eux \
    && wget -P $VOLTTRON_USER_HOME https://github.com/rabbitmq/rabbitmq-server/releases/download/v${RABBITMQ_VERSION}/${RABBITMQ_TAR} \
    && tar -xf $VOLTTRON_USER_HOME/${RABBITMQ_TAR} --directory $RMQ_ROOT \
    && rm ${VOLTTRON_USER_HOME}/${RABBITMQ_TAR} \
    && $RMQ_HOME/sbin/rabbitmq-plugins enable rabbitmq_management rabbitmq_federation rabbitmq_federation_management rabbitmq_shovel rabbitmq_shovel_management rabbitmq_auth_mechanism_ssl rabbitmq_trust_store
############################################


########################################
# The following lines should be run from any Dockerfile that
# is inheriting from this one as this will make the volttron
# run in the proper location.
#
# The user must be root at this point to allow gosu to work
########################################
USER root
WORKDIR ${VOLTTRON_USER_HOME}
ENTRYPOINT ["/startup/entrypoint.sh"]
CMD ["/startup/bootstart.sh"]
