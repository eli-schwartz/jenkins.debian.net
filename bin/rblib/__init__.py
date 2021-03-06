# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

from sqlalchemy import Table
from sqlalchemy.exc import NoSuchTableError, OperationalError

from .confparse import log
from .const import PGDATABASE, DB_METADATA, conn_db
from .utils import print_critical_message


def db_table(table_name):
    """Returns a SQLAlchemy Table objects to be used in queries
    using SQLAlchemy's Expressive Language.

    Arguments:
        table_name: a string corrosponding to an existing table name
    """
    try:
        return Table(table_name, DB_METADATA, autoload=True)
    except NoSuchTableError:
        log.error(
            "Table %s does not exist or schema for %s could not be loaded",
            table_name, PGDATABASE)
        raise


def query_db(query, *args, **kwargs):
    """Excutes a raw SQL query. Return depends on query type.

    Returns:
        select:
            list of tuples
        update or delete:
            the number of rows affected
        insert:
            None
    """
    try:
        result = conn_db.execute(query, *args, **kwargs)
    except OperationalError as ex:
        print_critical_message('Error executing this query:\n' + query)
        raise

    if result.returns_rows:
        return result.fetchall()
    elif result.supports_sane_rowcount() and result.rowcount > -1:
        return result.rowcount
    else:
        return None


def get_status_icon(status):
    table = {'reproducible': 'weather-clear.png',
             'FTBFS': 'weather-storm.png',
             'FTBR': 'weather-showers-scattered.png',
             '404': 'weather-severe-alert.png',
             'depwait': 'weather-snow.png',
             'not for us': 'weather-few-clouds-night.png',
             'not_for_us': 'weather-few-clouds-night.png',
             'untested': 'weather-clear-night.png',
             'blacklisted': 'error.png'}
    spokenstatus = status
    if status == 'unreproducible':
            status = 'FTBR'
    elif status == 'not for us':
            status = 'not_for_us'
    try:
        return (status, table[status], spokenstatus)
    except KeyError:
        log.error('Status ' + status + ' not recognized')
        return (status, '', spokenstatus)


def get_trailing_bug_icon(bug, bugs, package=None):
    html = ''
    if not package:
        for pkg in bugs.keys():
            if get_trailing_bug_icon(bug, bugs, pkg):
                return get_trailing_bug_icon(bug, bugs, pkg)
    else:
        try:
            if bug in bugs[package].keys():
                html += '<span class="'
                if bugs[package][bug]['done']:
                    html += 'bug-done" title="#' + str(bug) + ', done">#'
                elif bugs[package][bug]['pending']:
                    html += 'bug-pending" title="#' + str(bug) + ', pending">P'
                elif bugs[package][bug]['patch']:
                    html += 'bug-patch" title="#' + str(bug) + ', with patch">+'
                else:
                    html += 'bug">'
                html += '</span>'
        except KeyError:
            pass
    return html
