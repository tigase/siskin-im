#
# swiftScript.swift
#
# Tigase iOS Messenger
# Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. Look for COPYING file in the top folder.
# If not, see http://www.gnu.org/licenses/.
#

# Script responsible for marking TODO: and FIXME: as warinings in comments during compilation

#import Foundation

TAGS="TODO:|FIXME:"
find "${SRCROOT}" \( \( -name "*.h" -or -name "*.m" -or -name "*.swift" \) -and -not -name "swiftScript.swift" \) -print0 | xargs -0 egrep --with-filename --line-number --only-matching "($TAGS).*\$" | perl -p -e "s/($TAGS)/ warning: \$1/"