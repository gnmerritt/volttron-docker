#! /usr/bin/env bash

# We are going to pre-setup the platform before running any of the environment.
if [[ -z /startup/setup-platform.py ]]; then
  echo "/startup/setup-platform.py does not exist.  The docker image must be corrupted"
  exit 1
fi

echo "Right before setup-platform.py is called I am calling printenv"
printenv

echo ""
echo "Running with python $(which python3) ($(python3 --version))"
echo "Running as $(whoami)"
echo ""

python3 /startup/setup-platform.py
setup_return=$?
if (( $setup_return != 0 )); then
  echo "error running setup-platform.py: ${setup_return}"
  exit $setup_return
fi

echo ""
echo "Platform setup complete, starting volttron"
echo ""

# Now spin up the volttron platform
volttron -vv
volttron_retcode=$?
if (( $volttron_retcode != 0 )); then
  echo "volttron error: ${volttron_retcode}"
  exit $volttron_retcode
fi
