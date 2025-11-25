/// Generate the groups.ini file for forum.dlang.org.
module gengroups;

import std.algorithm;
import std.array;
import std.stdio;
import std.string;

struct DAlsoVia { string name, url; }
struct DGroupInfo { string internalName, publicName, navName, urlName, description, postMessage, notice, mlName; bool mlOnly, localOnly; DAlsoVia[string] alsoVia; }
struct DGroupSet { string id, name, shortName; DGroupInfo[] groups; bool visible; }

DGroupSet makeDGroupSet(string name, DGroupInfo[] groups, bool visible = true)
{
	auto shortName = name;
	shortName.skipOver("D Programming Language - ");
	auto id = shortName.toLower.replace(".", "-").replace(" ", "-");
	return DGroupSet(id, name, shortName, groups, visible);
}

DGroupInfo makeDGroupInfo(string internalName, string publicName, string navName, string urlName, string archiveName, string mlName, string description, bool mlOnly, bool bugzilla)
{
	auto info = DGroupInfo(internalName, publicName, navName, urlName, description.chomp(".").strip());
	info.mlOnly = mlOnly;
	if (!mlOnly)
		info.alsoVia["01-nntp"] = DAlsoVia("NNTP", `news://news.digitalmars.com/` ~ internalName);
	if (mlName)
	{
		info.mlName = mlName;
		info.alsoVia["02-ml"] = DAlsoVia("mailing list", `http://lists.puremagic.com/cgi-bin/mailman/listinfo/` ~ mlName.toLower());
	}
	if (bugzilla)
	{
		info.alsoVia["03-bugzilla"] = DAlsoVia("Bugzilla", `https://issues.dlang.org/`);
		info.postMessage =
			`You are viewing a Bugzilla message archive.<br>` ~
			`To report a bug, please visit the <a href="https://issues.dlang.org/">D Bugzilla</a> or `~
				`<a href="/newpost/digitalmars.D">post to digitalmars.D</a>.`;
	}
	if (internalName.startsWith("digitalmars.dip."))
	{
		info.notice =
			`Please read and understand the <a href="https://github.com/dlang/DIPs/blob/master/docs/guidelines-forums.md">DIP forum guidelines</a> before posting in this forum.`;
	}
	if (mlOnly)
		info.alsoVia["04-archive"] = DAlsoVia("archive", `http://lists.puremagic.com/pipermail/`~internalName.toLower());
	else
	if (archiveName)
		info.alsoVia["04-archive"] = DAlsoVia("archive", `http://www.digitalmars.com/d/archives/`~archiveName~`/`);
	return info;
}

DGroupInfo makeLocalGroupInfo(string internalName, string publicName, string navName, string urlName, string description)
{
	auto info = DGroupInfo(internalName, publicName, navName, urlName, description.chomp(".").strip());
	info.localOnly = true;
	return info;
}


void main()
{
	DGroupSet[] groupHierarchy =
	[
		//                  internalName                     publicName                  navName                     urlName                     archiveName                 mlName                      description                                                         mlOnly bugzilla
		makeDGroupSet("New users", [
			makeDGroupInfo("digitalmars.D.learn"           , "Learn"                   , "Learn"                   , "learn"                   , "digitalmars/D/learn"     , "Digitalmars-d-learn"     , "Questions about learning and using D"                             , false, false),
		]),
		makeDGroupSet("Community", [
			makeDGroupInfo("digitalmars.D"                 , "General"                 , "General"                 , "general"                 , "digitalmars/D"           , "Digitalmars-d"           , "Discussion of the D programming language"                         , false, false),
			makeDGroupInfo("digitalmars.D.announce"        , "Announce"                , "Announce"                , "announce"                , "digitalmars/D/announce"  , "Digitalmars-d-announce"  , "News and announcements for anything D related"                    , false, false),
		]),
		makeDGroupSet("Improvements", [
			makeDGroupInfo("digitalmars.dip.ideas"         , "DIP Ideas"               , "DIP Ideas"               , "dip.ideas"               , null                      , null                      , "Ideas for improving the D programming language"                   , false, false),
			makeDGroupInfo("digitalmars.dip.development"   , "DIP Development"         , "DIP Devel."              , "dip.development"         , null                      , null                      , "Development of D Improvement Proposals"                           , false, false),
		]),
		makeDGroupSet("Ecosystem", [
			makeDGroupInfo("D.gnu"                         , "GDC"                     , "GDC"                     , "gdc"                     , "D/gnu"                   , "D.gnu"                   , "GCC-based D Compiler"                                             , false, false),
			makeDGroupInfo("digitalmars.D.ldc"             , "LDC"                     , "LDC"                     , "ldc"                     , null                      , "digitalmars-d-ldc"       , "LLVM-based D Compiler"                                            , false, false),

			makeDGroupInfo("digitalmars.D.debugger"        , "Debuggers"               , "Debuggers"               , "debugger"                , "digitalmars/D/debugger"  , "Digitalmars-d-debugger"  , "Debuggers for D"                                                  , false, false),
			makeDGroupInfo("digitalmars.D.ide"             , "IDEs"                    , "IDEs"                    , "ide"                     , "digitalmars/D/ide"       , "Digitalmars-d-ide"       , "Integrated Development Environments for D"                        , false, false),

			makeDGroupInfo("digitalmars.D.dwt"             , "DWT"                     , "DWT"                     , "dwt"                     , "digitalmars/D/dwt"       , "Digitalmars-d-dwt"       , "Discussion of the D Widget Toolkit"                               , false, false),
		]),
		makeDGroupSet("Development", [
			makeDGroupInfo("digitalmars.D.internals"       , "Internals"               , "Internals"               , "internals"               , null                      , null                      , "Discussion of language development and internals"                 , false, false),
			makeDGroupInfo("digitalmars.D.bugs"            , "Issues"                  , "Issues"                  , "issues"                  , "digitalmars/D/bugs"      , "Digitalmars-d-bugs"      , "Bug reports for D compiler and library"                           , false, true ),
			makeDGroupInfo("dmd-beta"                      , "Beta"                    , "Beta"                    , "beta"                    , null                      , "dmd-beta"                , "Notifications and discussion of D beta versions"                  , true , false),
			makeDGroupInfo("dmd-internals"                 , "DMD"                     , "DMD"                     , "dmd"                     , null                      , "dmd-internals"           , "Compiler internal design and implementation"                      , true , false),
			makeDGroupInfo("phobos"                        , "Phobos"                  , "Phobos"                  , "phobos"                  , null                      , "phobos"                  , "Standard library design and implementation"                       , true , false),
			makeDGroupInfo("D-runtime"                     , "Druntime"                , "Druntime"                , "druntime"                , null                      , "D-runtime"               , "Runtime library design and implementation"                        , true , false),
			makeDGroupInfo("Dlang-study"                   , "Study"                   , "Study"                   , "study"                   , null                      , "Dlang-study"             , "Study groups for D programming language design"                   , true , false),
		]),
		makeDGroupSet("Turkish", [
			makeDGroupInfo("digitalmars.D.turkish.genel"   , "Genel"                   , "Genel"                   , "turkish.genel"           , null                      , null                      , "D programlama dili ile ilgili konular"                            , false, false),
			makeDGroupInfo("digitalmars.D.turkish.duyuru"  , "Duyuru"                  , "Duyuru"                  , "turkish.duyuru"          , null                      , null                      , "D programlama dili ile ilgili duyurular ve haberler"              , false, false),
		]),
		makeDGroupSet("Unused", [
			makeDGroupInfo("dmd-concurrency"               , "Concurrency"             , "Concurrency"             , "concurrency"             , null                      , "dmd-concurrency"         , "Design of concurrency features in D and standard library"         , true , false),

			makeDGroupInfo("digitalmars.D.dtl"             , "digitalmars.D.dtl"       , "digitalmars.D.dtl"       , "digitalmars.D.dtl"       , "digitalmars/D/dtl"       , "Digitalmars-d-dtl"       , "Developing the D Template Library"                                , false, false),
			makeDGroupInfo("DMDScript"                     , "DMDScript"               , "DMDScript"               , "DMDScript"               , "DMDScript"               , null                      , "General discussion of DMDScript"                                  , false, false),
			makeDGroupInfo("digitalmars.empire"            , "digitalmars.empire"      , "digitalmars.empire"      , "digitalmars.empire"      , "digitalmars/empire"      , null                      , "General discussion of Empire, the Wargame of the Century"         , false, false),
			makeDGroupInfo("D"                             , "D"                       , "D"                       , "D"                       , ""                        , null                      , "Retired, use digitalmars.D instead"                               , false, false),
		], false),
		makeDGroupSet("C and C++", [
			makeDGroupInfo("c++"                           , "c++"                     , "c++"                     , "c++"                     , "c++"                     , null                      , "General discussion of DMC++ compiler"                             , false, false),
			makeDGroupInfo("c++.announce"                  , "c++.announce"            , "c++.announce"            , "c++.announce"            , "c++/announce"            , null                      , "Announcements about C++"                                          , false, false),
			makeDGroupInfo("c++.atl"                       , "c++.atl"                 , "c++.atl"                 , "c++.atl"                 , "c++/atl"                 , null                      , "Microsoft's Advanced Template Library"                            , false, false),
			makeDGroupInfo("c++.beta"                      , "c++.beta"                , "c++.beta"                , "c++.beta"                , "c++/beta"                , null                      , "Test versions of various C++ products"                            , false, false),
			makeDGroupInfo("c++.chat"                      , "c++.chat"                , "c++.chat"                , "c++.chat"                , "c++/chat"                , null                      , "Off topic discussions"                                            , false, false),
			makeDGroupInfo("c++.command-line"              , "c++.command-line"        , "c++.command-line"        , "c++.command-line"        , "c++/command-line"        , null                      , "Command line tools"                                               , false, false),
			makeDGroupInfo("c++.dos"                       , "c++.dos"                 , "c++.dos"                 , "c++.dos"                 , "c++/dos"                 , null                      , "DMC++ and DOS"                                                    , false, false),
			makeDGroupInfo("c++.dos.16-bits"               , "c++.dos.16-bits"         , "c++.dos.16-bits"         , "c++.dos.16-bits"         , "c++/dos/16-bits"         , null                      , "16 bit DOS topics"                                                , false, false),
			makeDGroupInfo("c++.dos.32-bits"               , "c++.dos.32-bits"         , "c++.dos.32-bits"         , "c++.dos.32-bits"         , "c++/dos/32-bits"         , null                      , "32 bit extended DOS topics"                                       , false, false),
			makeDGroupInfo("c++.idde"                      , "c++.idde"                , "c++.idde"                , "c++.idde"                , "c++/idde"                , null                      , "The Digital Mars Integrated Development and Debugging Environment", false, false),
			makeDGroupInfo("c++.mfc"                       , "c++.mfc"                 , "c++.mfc"                 , "c++.mfc"                 , "c++/mfc"                 , null                      , "Microsoft Foundation Classes"                                     , false, false),
			makeDGroupInfo("c++.rtl"                       , "c++.rtl"                 , "c++.rtl"                 , "c++.rtl"                 , "c++/rtl"                 , null                      , "C++ Runtime Library"                                              , false, false),
			makeDGroupInfo("c++.stl"                       , "c++.stl"                 , "c++.stl"                 , "c++.stl"                 , "c++/stl"                 , null                      , "Standard Template Library"                                        , false, false),
			makeDGroupInfo("c++.stl.hp"                    , "c++.stl.hp"              , "c++.stl.hp"              , "c++.stl.hp"              , "c++/stl/hp"              , null                      , "HP's Standard Template Library"                                   , false, false),
			makeDGroupInfo("c++.stl.port"                  , "c++.stl.port"            , "c++.stl.port"            , "c++.stl.port"            , "c++/stl/port"            , null                      , "STLPort Standard Template Library"                                , false, false),
			makeDGroupInfo("c++.stl.sgi"                   , "c++.stl.sgi"             , "c++.stl.sgi"             , "c++.stl.sgi"             , "c++/stl/sgi"             , null                      , "SGI's Standard Template Library"                                  , false, false),
			makeDGroupInfo("c++.stlsoft"                   , "c++.stlsoft"             , "c++.stlsoft"             , "c++.stlsoft"             , "c++/stlsoft"             , null                      , "Stlsoft products"                                                 , false, false),
			makeDGroupInfo("c++.windows"                   , "c++.windows"             , "c++.windows"             , "c++.windows"             , "c++/windows"             , null                      , "Writing C++ code for Microsoft Windows"                           , false, false),
			makeDGroupInfo("c++.windows.16-bits"           , "c++.windows.16-bits"     , "c++.windows.16-bits"     , "c++.windows.16-bits"     , "c++/windows/16-bits"     , null                      , "16 bit Windows topics"                                            , false, false),
			makeDGroupInfo("c++.windows.32-bits"           , "c++.windows.32-bits"     , "c++.windows.32-bits"     , "c++.windows.32-bits"     , "c++/windows/32-bits"     , null                      , "32 bit Windows topics"                                            , false, false),
			makeDGroupInfo("c++.wxwindows"                 , "c++.wxwindows"           , "c++.wxwindows"           , "c++.wxwindows"           , "c++/wxwindows"           , null                      , "wxWindows"                                                        , false, false),
		], false),
		makeDGroupSet("Local", [
			makeLocalGroupInfo("local.test"                , "Test"                    , "Test"                    , "local.test"              , "Local test group"),
		], false),
	];

	auto f = File("groups.ini", "wb");
	f.writeln("# Generated by gengroups.d - do not edit");

	foreach (set; groupHierarchy)
	{
		f.writeln();
		f.writeln("[sets.", set.id, "]");
		f.writeln("name=", set.name);
		f.writeln("shortName=", set.shortName);
		f.writeln("visible=", set.visible);

		foreach (group; set.groups)
		{
			f.writeln();
			f.writeln("[groups.", group.urlName.replace(".", "-"), "]");
			f.writeln("internalName=", group.internalName);
			f.writeln("publicName=", group.publicName);
			f.writeln("navName=", group.navName);
			f.writeln("urlName=", group.urlName);
			if (group.internalName != group.urlName)
				f.writeln("urlAliases=", [group.internalName]);
			f.writeln("groupSet=", set.id);
			f.writeln("description=", group.description);
			if (group.postMessage)
				f.writeln("postMessage=", group.postMessage);
			if (group.notice)
				f.writeln("notice=", group.notice);
			if (group.localOnly)
			{
				f.writeln("sinkType=local");
			}
			else if (group.mlOnly)
			{
				f.writeln("sinkType=smtp");
				f.writeln("sinkName=puremagic");
			}
			else
			{
				f.writeln("sinkType=nntp");
				f.writeln("sinkName=digitalmars");
			}
			foreach (k; group.alsoVia.keys.sort())
			{
				auto av = group.alsoVia[k];
				f.writefln("alsoVia.%s.name=%s", k, av.name);
				f.writefln("alsoVia.%s.url=%s", k, av.url);
			}
			f.writeln("announce=", group.urlName == "announce");
			f.writeln("captcha=", group.internalName.startsWith("digitalmars.D.turkish.") ? "none" : "dcaptcha");
		}
	}

	f = File("sources/mailman/puremagic.ini", "wb");
	f.writeln("# Generated by gengroups.d - do not edit");
	f.writeln("baseURL = http://lists.puremagic.com/pipermail/");
	auto lists = groupHierarchy.map!(set => set.groups).joiner.filter!(group => group.mlOnly).map!(group => group.mlName).filter!(a=>a).array;
	f.writeln("lists = ", lists.join(","));
	f.writeln();
	f.writeln("[shadowLists]");
	foreach (group; groupHierarchy.map!(set => set.groups).joiner.filter!(group => group.mlName && !group.mlOnly))
	{
		auto name = group.mlName.replace(".", "-").toLower();
		f.writefln("%s.list = %s" , name, group.mlName);
		f.writefln("%s.group = %s", name, group.internalName);
		f.writeln();
	}
}
