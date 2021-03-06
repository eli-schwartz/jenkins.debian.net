#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Based on reproducible_json.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build the reproducible.json and reproducibe-tracker.json files, to provide nice datasources


import os
import json
import apt_pkg
apt_pkg.init_system()
import tempfile
import subprocess

from rblib import query_db
from rblib.confparse import log
from rblib.const import (
    DISTRO_URL,
    REPRODUCIBLE_JSON, REPRODUCIBLE_TRACKER_JSON,
    filter_query,
)

output = []
output4tracker = []

log.info('Creating json dump of current reproducible status')

# filter_query is defined in reproducible_common.py and excludes some FTBFS issues
query = "SELECT s.name, r.version, s.suite, s.architecture, r.status, r.build_date " + \
        "FROM results AS r JOIN sources AS s ON r.package_id = s.id "+ \
        "WHERE status != '' AND status NOT IN ('not for us', '404', 'blacklisted' ) AND (( status != 'FTBFS' ) OR " \
        " ( status = 'FTBFS' and r.package_id NOT IN (SELECT n.package_id FROM NOTES AS n WHERE " + filter_query + " )))"

result = sorted(query_db(query))
log.info('\tprocessing ' + str(len(result)))

keys = ['package', 'version', 'suite', 'architecture', 'status', 'build_date']
crossarchkeys = ['package', 'version', 'suite', 'status']
archdetailkeys = ['architecture', 'version', 'status', 'build_date']

# crossarch is a dictionary of all packages used to build a summary of the
# package's test results across all archs (for suite=unstable only)
crossarch = {}

crossarchversions = {}
for row in result:
    pkg = dict(zip(keys, row))
    log.debug(pkg)
    output.append(pkg)

    # tracker.d.o should only care about results in testing
    if pkg['suite'] == 'buster':

        package = pkg['package']
        if package in crossarch:
            # compare statuses to get cross-arch package status
            status1 = crossarch[package]['status']
            status2 = pkg['status']
            newstatus = ''

            # compare the versions (only keep most up to date!)
            version1 = crossarch[package]['version']
            version2 = pkg['version']
            versionscompared = apt_pkg.version_compare(version1, version2);

            # if version1 > version2,
            # skip the package results we are currently inspecting
            if (versionscompared > 0):
                continue

            # if version1 < version2,
            # delete the package results with the older version
            elif (versionscompared < 0):
                newstatus = status2
                # remove the old package information from the list
                archlist = crossarch[package]['architecture_details']
                newarchlist = [a for a in archlist if a['version'] != version1]
                crossarch[package]['architecture_details'] = newarchlist

            # if version1 == version 2,
            # we are comparing status for the same (most recent) version
            else:
                if 'FTBFS' in [status1, status2]:
                    newstatus = 'FTBFS'
                elif 'unreproducible' in [status1, status2]:
                    newstatus = 'unreproducible'
                elif 'reproducible' in [status1, status2]:
                    newstatus = 'reproducible'
                else:
                    newstatus = 'depwait'

            # update the crossarch status and version
            crossarch[package]['status'] = newstatus
            crossarch[package]['version'] = version2

            # add arch specific test results to architecture_details list
            newarchdetails = {key:pkg[key] for key in archdetailkeys}
            crossarch[package]['architecture_details'].append(newarchdetails)


        else:
            # add package to crossarch
            crossarch[package] = {key:pkg[key] for key in crossarchkeys}
            crossarch[package]['architecture_details'] = \
                [{key:pkg[key] for key in archdetailkeys}]

output4tracker = list(crossarch.values())

for data, target in (
    (output, REPRODUCIBLE_JSON),
    # json for tracker.d.o, thanks to #785531
    (output4tracker, REPRODUCIBLE_TRACKER_JSON),
):
    tmpfile = tempfile.mkstemp(dir=os.path.dirname(target))[1]
    with open(tmpfile, 'w') as fd:
        json.dump(data, fd, indent=4, sort_keys=True)
    os.rename(tmpfile, target)
    os.chmod(target, 0o644)
    log.info("%s/%s has been updated.", DISTRO_URL, os.path.basename(target))

    # Write compressed version
    compressed = '{}.bz2'.format(target)
    tmpfile = tempfile.mkstemp(dir=os.path.dirname(compressed))[1]
    with open(tmpfile, 'w') as fd:
        subprocess.check_call(('bzip2', '-9c', target), stdout=fd)
    os.rename(tmpfile, compressed)
    os.chmod(compressed, 0o644)
    log.info("%s/%s has been updated.", DISTRO_URL, os.path.basename(compressed))
