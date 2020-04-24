FROM centos:7
EXPOSE 5000

RUN rpm -iUvh http://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/e/epel-release-7-12.noarch.rpm

RUN yum -y update
RUN yum -y groupinstall "Development tools"
RUN yum -y install wget gcc-c++ openssl-devel \
                   postgresql-devel mysql-devel \
                   git libffi-devel libxml2-devel libxml2 \
                   libxslt-devel zlib1g-dev libxslt http-parser uwsgi

# Install Node...

RUN curl -sL https://rpm.nodesource.com/setup_12.x | bash -
RUN yum clean all && yum makecache fast
RUN yum install -y gcc-c++ make
RUN yum install -y nodejs

# Install Python...

ENV PYTHON_VER=3.6
ENV PYTHON_PRG=/usr/bin/python${PYTHON_VER}
ENV PYTHON_ENV=/opt/.venv
ENV PYTHON_LIB=${VIRTUAL_ENV}/lib/python${PYTHON_VER}

RUN echo -e \
    "\tPYTHON VERSION : $PYTHON_VER\n" \
    "\tPYTHON PROGRAM : $PYTHON_PRG\n" \
    "\tPYTHON VIRTUAL : $PYTHON_ENV\n" \
    "\tPYTHON LIBRARY : $PYTHON_LIB\n"

RUN yum -y install https://centos7.iuscommunity.org/ius-release.rpm
RUN yum -y install python${PYTHON_VER//.} python${PYTHON_VER//.}-pip python${PYTHON_VER//.}-devel python${PYTHON_VER//.}-virtualenv

RUN ${PYTHON_PRG} -m virtualenv --python=${PYTHON_PRG} ${PYTHON_ENV}
ENV PATH="$PYTHON_ENV/bin:$PATH"

# install locale
RUN localedef -c -f UTF-8 -i en_US en_US.UTF-8
ENV LC_ALL=en_US.utf-8
ENV LANG=en_US.utf-8

RUN pip install cookiecutter pipenv
RUN yum install -y openssl which

ENV PIPENV_VENV_IN_PROJECT=/opt/venv 

WORKDIR /opt