WORKDIR="/tmp"

INSTANCE_TEMPLATE="gh:inveniosoftware/cookiecutter-invenio-instance"
INVENIO_VERSION=v3.2
PROJECT_NAME=B2SHARE
PROJECT_SITE=b2share.eudat.eu
INSTANCE_NAME=b2share

GITHUB_REPO=HarryKodden/b2share-new
DESCRIPTION='EUDAT Collaborative Data Infrastructure.'
AUTHOR_NAME=EUDAT
AUTHOR_EMAIL=info@eudat.eu

DATABASE=postgresql
ELASTICSEARCH=7
DATAMODEL=Custom

MODULE_TEMPLATE="gh:inveniosoftware/cookiecutter-invenio-module"
MODULE_NAME=b2share_foo
MODULE_DESCRIPTION="MODULE FOO for EUDAT Collaborative Data Infrastructure."
MODULE_PREFIX=FOO

INVENIO_INSTANCE_PATH=/opt/invenio/var/instance

ADMIN_USERNAME="admin@${PROJECT_SITE}"
ADMIN_PASSWORD=changeme

echo "Building: ${INSTANCE_NAME}..."
docker build -t ${INSTANCE_NAME} .

echo "Start templating instance..."
sudo rm -rf ${WORKDIR}/${INSTANCE_NAME}
docker run -v /tmp:/tmp ${INSTANCE_NAME} cookiecutter ${INSTANCE_TEMPLATE} --checkout ${INVENIO_VERSION} --no-input -o ${WORKDIR} \
          project_name=${PROJECT_NAME} \
          project_site=${PROJECT_SITE} \
          package_name=${INSTANCE_NAME} \
          github_repo=${GITHUB_REPO} \
          description="${DESCRIPTION}" \
          author_name=${AUTHOR_NAME} \
          author_email=${AUTHOR_EMAIL} \
          database=${DATABASE} \
          elasticsearch=${ELASTICSEARCH} \
          datamodel=${DATAMODEL}

echo "Start templating module..."
sudo rm -rf ${WORKDIR}/${MODULE_NAME}
docker run -v /tmp:/tmp ${INSTANCE_NAME} cookiecutter ${MODULE_TEMPLATE} --no-input -o ${WORKDIR} \
          project_name=${PROJECT_NAME}_${MODULE_PREFIX} \
          package_name=${MODULE_NAME} \
          github_repo=${GITHUB_REPO} \
          description="${MODULE_DESCRIPTION}" \
          author_name=${AUTHOR_NAME} \
          author_email=${AUTHOR_EMAIL} \
          config_prefix=${MODULE_PREFIX}

sudo mkdir -p ${WORKDIR}/${INSTANCE_NAME}/${INSTANCE_NAME}/modules
sudo tee -a ${WORKDIR}/${INSTANCE_NAME}/${INSTANCE_NAME}/modules/__init__.py > /dev/null <<EOT
"""${PROJECT_NAME} Modules"""
EOT

sudo cp -r ${WORKDIR}/${MODULE_NAME}/${MODULE_NAME} ${WORKDIR}/${INSTANCE_NAME}/${INSTANCE_NAME}/modules

sudo tee -a ${WORKDIR}/${INSTANCE_NAME}/entry_points.txt > /dev/null <<EOT
[invenio_base.apps]
${MODULE_NAME} = ${INSTANCE_NAME}.modules.${MODULE_NAME}:${PROJECT_NAME}_${MODULE_PREFIX}

[invenio_base.api_apps]
${MODULE_NAME} = ${INSTANCE_NAME}.modules.${MODULE_NAME}:${PROJECT_NAME}_${MODULE_PREFIX}

[invenio_base.blueprints]
${MODULE_NAME} = ${INSTANCE_NAME}.modules.${MODULE_NAME}.views:blueprint
EOT

sudo sed -i "/^setup(*/i def my_setup(**kwargs):\n\
    with open('entry_points.txt', 'r') as f:\n\
    entry_point = None\n\
    for line in [l.rstrip() for l in f]:\n\
        if line.startswith('[') and line.endswith(']'):\n\
            entry_point = line.lstrip('[').rstrip(']')\n\
        else:\n\
            if 'entry_points' not in kwargs:\n\
                kwargs['entry_points'] = {}\n\
            if entry_point not in kwargs['entry_points']:\n\
                kwargs['entry_points'][entry_point] = []\n\
            if entry_point and line > '':\n\
                kwargs['entry_points'][entry_point].append(line)\n\
    setup(**kwargs)\n\
" ${WORKDIR}/${INSTANCE_NAME}/setup.py

sudo sed -i 's/^setup(/my_setup(/' ${WORKDIR}/${INSTANCE_NAME}/setup.py

sudo sed -i "/^\[packages\]/a \
numpy = \">1.16.0\"\n\
email_validator = \">=1.0.5\"\n\
sqlalchemy = \"<1.3.6\"\n\
celery = \">=4.4.2\"\n\
wtforms = \"<2.3.0\"\
" ${WORKDIR}/${INSTANCE_NAME}/Pipfile

exit 1
# Adjust ip addresses of allowed host
#ALLOWED_HOSTS=`ifconfig |grep 'inet .* netmask' | awk '{printf(",'\''%s'\''", $2);}'`
#docker exec ${INSTANCE_NAME}-bootstrap sed -i 's/APP_ALLOWED_HOSTS = \[\(.*\)\]/APP_ALLOWED_HOSTS = [\1'"${ALLOWED_HOSTS}"']/' ${WORKDIR}/${INSTANCE_NAME}/${INSTANCE_NAME}/config.py
sudo sed -i 's/APP_ALLOWED_HOSTS = .*/APP_ALLOWED_HOSTS = None/' ${WORKDIR}/${INSTANCE_NAME}/${INSTANCE_NAME}/config.py

DOMAIN="192.168.191.108"

dd if=/dev/urandom of=~/.rnd bs=256 count=1
sudo openssl req \
    -new -sha256 \
    -subj "/CN=$DOMAIN" \
    -key ${WORKDIR}/${INSTANCE_NAME}/docker/nginx/test.key \
    -out ${WORKDIR}/${INSTANCE_NAME}/docker/nginx/test.csr
sudo openssl x509 -req -sha256 \
    -days 3650 \
    -in  ${WORKDIR}/${INSTANCE_NAME}/docker/nginx/test.csr \
    -out ${WORKDIR}/${INSTANCE_NAME}/docker/nginx/test.crt \
    -signkey ${WORKDIR}/${INSTANCE_NAME}/docker/nginx/test.key

sudo bash -c "cat ${WORKDIR}/${INSTANCE_NAME}/docker/nginx/test.crt ${WORKDIR}/${INSTANCE_NAME}/docker/nginx/test.key > ${WORKDIR}/${INSTANCE_NAME}/docker/haproxy/haproxy_cert.pem"

# Make sure we have a clean sheet...
docker rm -f ${INSTANCE_NAME}-base 2>/dev/null
docker rm -f ${INSTANCE_NAME}-bootstrap 2>/dev/null

echo "Create image"
docker create -v /tmp:/tmp --name ${INSTANCE_NAME}-bootstrap ${INSTANCE_NAME} tail -f /dev/null

echo "Start image"
docker start ${INSTANCE_NAME}-bootstrap

echo "Bootstrapping image..."
docker exec ${INSTANCE_NAME}-bootstrap cp -r /tmp/${INSTANCE_NAME} /opt/${INSTANCE_NAME}

# Share virtualenv with pipenv project virtual environment
docker exec ${INSTANCE_NAME}-bootstrap ln -s /opt/.venv /opt/${INSTANCE_NAME}

# Add APP & API ini scripts...
docker exec ${INSTANCE_NAME}-bootstrap bash -c "mkdir -p ${INVENIO_INSTANCE_PATH}; cp /opt/${INSTANCE_NAME}/docker/uwsgi/*.ini ${INVENIO_INSTANCE_PATH}"

# All set ! Now start bootstrapping...
docker exec ${INSTANCE_NAME}-bootstrap bash -c "cd /opt/${INSTANCE_NAME}; ./scripts/bootstrap"

echo "Finalizing image !"
docker commit -c "ENV INVENIO_INSTANCE_PATH ${INVENIO_INSTANCE_PATH}" -c "WORKDIR /opt/${INSTANCE_NAME}" ${INSTANCE_NAME}-bootstrap ${INSTANCE_NAME}-base
docker stop ${INSTANCE_NAME}-bootstrap
docker rm ${INSTANCE_NAME}-bootstrap

echo "building services..."
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-services.yml build)

echo "(Re-)starting services..."
sudo sed -i 's#command: \["uwsgi /opt/invenio/var/instance/uwsgi_ui.ini"\]#command: \["tail -f /dev/null"\]#' ${WORKDIR}/${INSTANCE_NAME}/docker-compose.full.yml
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml down -v)
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml up -d)

echo "Waiting for services to be initialised..."
(cd ${WORKDIR}/${INSTANCE_NAME}; ./docker/wait-for-services.sh)

echo "Starting Frontend..."
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml run --rm web-ui ./scripts/setup)

echo "create admin user..."
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml exec web-ui ${INSTANCE_NAME} users create --active ${ADMIN_USERNAME} --password ${ADMIN_PASSWORD})
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml exec web-ui ${INSTANCE_NAME} roles add ${ADMIN_USERNAME} admin)

echo "Copy static content..."
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml exec web-ui cp -r /opt/.venv/var/instance/static ${INVENIO_INSTANCE_PATH})

echo "Start WEB UI !"
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml exec web-ui pip install git+https://github.com/Supervisor/supervisor)
(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml exec web-ui bash -c "cat > /opt/supervisord.conf <<EOT
[supervisord]
nodaemon=false
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
[supervisorctl]
serverurl=unix:///var/run/supervisor.sock
[program:${INSTANCE_NAME}]
command=uwsgi /opt/invenio/var/instance/uwsgi_ui.ini
EOT")

(cd ${WORKDIR}/${INSTANCE_NAME}; docker-compose -f docker-compose.full.yml exec web-ui supervisord -c /opt/supervisord.conf)