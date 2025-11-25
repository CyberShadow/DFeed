/*  Copyright (C) 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/// Path resolution with site overlay support.
///
/// Files are searched in order:
///   1. site/     (site-specific, highest priority)
///   2. defaults/ (generic fallback)
///
/// This allows site-specific configuration and branding to override
/// generic defaults without modifying the core DFeed repository.
module dfeed.paths;

import std.file : exists;
import std.path : buildPath, dirSeparator;
import std.typecons : tuple;

immutable string[] siteSearchPaths = ["site", "site-defaults"];

/// Resolve the location of a site file through the overlay.
/// Path is relative to site root, e.g. "config/site.ini" or "web/skel.htt".
/// Returns the first overlay where the file is found,
/// or null if the file is not found in any overlay.
string resolveSiteFileBase(string relativePath)
{
    foreach (base; siteSearchPaths)
    {
        auto fullPath = buildPath(base, relativePath);
        if (exists(fullPath))
            return base ~ dirSeparator;
    }

    return null;
}

/// Resolve a site file through the overlay.
/// Path is relative to site root, e.g. "config/site.ini" or "web/skel.htt"
string resolveSiteFile(string relativePath)
{
    auto base = resolveSiteFileBase(relativePath);
    if (!base)
    {
        // Return first path for error messages (file doesn't exist anywhere)
        base = siteSearchPaths[0];
    }
    return buildPath(base, relativePath);
}

/// Resolve the location of a static file through the overlay.
/// Returns the base directory for serving `relativePath`,
/// or null if the file doesn't exist anywhere.
/// `relativePath` is expected to start with `/` (root-relative web path).
auto resolveStaticFileBase(string webPath)
{
    import std.algorithm.searching : skipOver;
    import std.exception : enforce;

    // Convert web path to relative path
    auto relativePath = webPath;
    relativePath.skipOver("/")
        .enforce("Web path must start with /");
    relativePath = buildPath("web", "static", relativePath);

    auto base = resolveSiteFileBase(relativePath);
    if (!base)
        return null;
    return base.buildPath("web", "static") ~ dirSeparator;
}
