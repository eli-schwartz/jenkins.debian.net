#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import os
import csv
import hashlib
import pystache
from urllib.parse import urljoin
from sqlalchemy import MetaData, create_engine

from .confparse import (
    __location__,
    args,
    conf_distro,
    log,
    DISTRO,
)

# tested suites
SUITES = conf_distro['suites'].split()
# tested architectures
ARCHS = conf_distro['archs'].split()
# defaults
defaultsuite = conf_distro['defaultsuite']
defaultarch = conf_distro['defaultarch']

BIN_PATH = __location__
BASE = conf_distro['basedir']
TEMPLATE_PATH = conf_distro['templates']
PKGSET_DEF_PATH = '/srv/reproducible-results'
TEMP_PATH = conf_distro['tempdir']

REPRODUCIBLE_STYLES = os.path.join(BASE, conf_distro['css'])

DISTRO_URI = '/' + conf_distro['distro_root']
DISTRO_BASE = os.path.join(BASE, conf_distro['distro_root'])

DBD_URI = os.path.join(DISTRO_URI, conf_distro['diffoscope_html'])
DBDTXT_URI = os.path.join(DISTRO_URI, conf_distro['diffoscope_txt'])
LOGS_URI = os.path.join(DISTRO_URI, conf_distro['buildlogs'])
DIFFS_URI = os.path.join(DISTRO_URI, conf_distro['logdiffs'])
NOTES_URI = os.path.join(DISTRO_URI, conf_distro['notes'])
ISSUES_URI = os.path.join(DISTRO_URI, conf_distro['issues'])
RB_PKG_URI = os.path.join(DISTRO_URI, conf_distro['packages'])
RBUILD_URI = os.path.join(DISTRO_URI, conf_distro['rbuild'])
HISTORY_URI = os.path.join(DISTRO_URI, conf_distro['pkghistory'])
BUILDINFO_URI = os.path.join(DISTRO_URI, conf_distro['buildinfo'])
DBD_PATH = BASE + DBD_URI
DBDTXT_PATH = BASE + DBDTXT_URI
LOGS_PATH = BASE + LOGS_URI
DIFFS_PATH = BASE + DIFFS_URI
NOTES_PATH = BASE + NOTES_URI
ISSUES_PATH = BASE + ISSUES_URI
RB_PKG_PATH = BASE + RB_PKG_URI
RBUILD_PATH = BASE + RBUILD_URI
HISTORY_PATH = BASE + HISTORY_URI
BUILDINFO_PATH = BASE + BUILDINFO_URI

REPRODUCIBLE_JSON = os.path.join(DISTRO_BASE, conf_distro['json_out'])
REPRODUCIBLE_TRACKER_JSON = os.path.join(DISTRO_BASE, conf_distro['tracker.json_out'])

REPRODUCIBLE_URL = conf_distro['base_url']
DISTRO_URL = urljoin(REPRODUCIBLE_URL, conf_distro['distro_root'])
DISTRO_DASHBOARD_URI = os.path.join(DISTRO_URI, conf_distro['landing_page'])
JENKINS_URL = conf_distro['jenkins_url']

# global package set definitions
# META_PKGSET[pkgset_id] = (pkgset_name, pkgset_group)
# csv file columns: (pkgset_group, pkgset_name)
META_PKGSET = []
with open(os.path.join(BIN_PATH, 'reproducible_pkgsets.csv'), newline='') as f:
    for line in csv.reader(f):
        META_PKGSET.append((line[1], line[0]))

# DATABSE CONSTANT
PGDATABASE = 'reproducibledb'



# init the database data and connection
if not args.skip_database_connection:
    DB_ENGINE = create_engine("postgresql:///%s" % PGDATABASE)
    DB_METADATA = MetaData(DB_ENGINE)  # Get all table definitions
    conn_db = DB_ENGINE.connect()      # the local postgres reproducible db

for key, value in conf_distro.items():
    log.debug('%-16s: %s', key, value)
log.debug("BIN_PATH:\t" + BIN_PATH)
log.debug("BASE:\t\t" + BASE)
log.debug("DISTRO:\t\t" + DISTRO)
log.debug("DBD_URI:\t\t" + DBD_URI)
log.debug("DBD_PATH:\t" + DBD_PATH)
log.debug("DBDTXT_URI:\t" + DBDTXT_URI)
log.debug("DBDTXT_PATH:\t" + DBDTXT_PATH)
log.debug("LOGS_URI:\t" + LOGS_URI)
log.debug("LOGS_PATH:\t" + LOGS_PATH)
log.debug("DIFFS_URI:\t" + DIFFS_URI)
log.debug("DIFFS_PATH:\t" + DIFFS_PATH)
log.debug("NOTES_URI:\t" + NOTES_URI)
log.debug("ISSUES_URI:\t" + ISSUES_URI)
log.debug("NOTES_PATH:\t" + NOTES_PATH)
log.debug("ISSUES_PATH:\t" + ISSUES_PATH)
log.debug("RB_PKG_URI:\t" + RB_PKG_URI)
log.debug("RB_PKG_PATH:\t" + RB_PKG_PATH)
log.debug("RBUILD_URI:\t" + RBUILD_URI)
log.debug("RBUILD_PATH:\t" + RBUILD_PATH)
log.debug("HISTORY_URI:\t" + HISTORY_URI)
log.debug("HISTORY_PATH:\t" + HISTORY_PATH)
log.debug("BUILDINFO_URI:\t" + BUILDINFO_URI)
log.debug("BUILDINFO_PATH:\t" + BUILDINFO_PATH)
log.debug("REPRODUCIBLE_JSON:\t" + REPRODUCIBLE_JSON)
log.debug("JENKINS_URL:\t\t" + JENKINS_URL)
log.debug("REPRODUCIBLE_URL:\t" + REPRODUCIBLE_URL)
log.debug("DISTRO_URL:\t" + DISTRO_URL)

if args.ignore_missing_files:
    log.warning("Missing files will be ignored!")

tab = '  '

# take a SHA1 of the css page for style version
hasher = hashlib.sha1()
with open(REPRODUCIBLE_STYLES, 'rb') as f:
        hasher.update(f.read())
REPRODUCIBLE_STYLE_SHA1 = hasher.hexdigest()

# Templates used for creating package pages
renderer = pystache.Renderer()
status_icon_link_template = renderer.load_template(
    TEMPLATE_PATH + '/status_icon_link')
default_page_footer_template = renderer.load_template(
    TEMPLATE_PATH + '/default_page_footer')
pkg_legend_template = renderer.load_template(
    TEMPLATE_PATH + '/pkg_symbol_legend')
project_links_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'project_links'))
main_navigation_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'main_navigation'))
basic_page_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'basic_page'))

try:
    JOB_URL = os.environ['JOB_URL']
except KeyError:
    JOB_URL = ''
    JOB_NAME = ''
else:
    JOB_NAME = os.path.basename(JOB_URL[:-1])
