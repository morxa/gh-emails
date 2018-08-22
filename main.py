#! /usr/bin/env python3
# -*- coding: utf-8 -*-
# vim:fenc=utf-8
#
# Copyright © 2018 Till Hofmann <hofmann@kbsg.rwth-aachen.de>
#
# Distributed under terms of the MIT license.

"""
Send detailed commit information on GitHub push events.
"""

import github_webhook
import flask
import os
import subprocess

app = flask.Flask(__name__)
webhook = github_webhook.Webhook(app, secret=os.environ.get('GITHUB_SECRET'))

@app.route('/')
def hello_world():
    return 'Hello, world!'

@webhook.hook()
def on_push(data):
    script_env = os.environ.copy()
    full_name =  data['repository']['full_name']
    repos_dir = os.environ.get('REPOS_DIR',
                               os.path.join(os.environ.get('PWD'), 'git'))
    script_env['REPO_DIR'] = os.path.join(repos_dir, full_name)
    cmd = ['notify.sh', data['ref'], data['before'], data['after'], full_name]
    subprocess.Popen(cmd, env=script_env, stdout=None, stderr=None)
    return "Processed push to {}.".format(full_name)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
