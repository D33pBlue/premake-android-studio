-- Android Studio Premake Module

-- Module interface
local m = {}

local p = premake
local project = p.project
local workspace = p.workspace
local config = p.config
local fileconfig = p.fileconfig
local tree = p.tree
local src_dirs = {}
	
-- remove this if you want to embed the module
dofile "_preload.lua"

-- Functions
function m.generate_workspace(wks)
	p.x('// workspace %s', wks.name)
	p.x('// auto-generated by premake-android-studio')
	p.push('buildscript {')
	p.push('repositories {')
	p.w('jcenter()')
	p.w('google()')
	p.pop('}') -- repositories
	p.push('dependencies {')
	
	if wks.gradleversion then
		p.x("classpath '%s'", wks.gradleversion)
	else
		p.w("classpath 'com.android.tools.build:gradle:3.1.4'")
	end  
	
	p.pop('}') -- dependencies
	p.pop('}') -- build scripts
	
	p.push('allprojects {')
	p.push('repositories {')
	p.w('jcenter()')
	p.w('google()')
	
	-- lib dirs for .aar and .jar files
	dir_list = nil
	for prj in workspace.eachproject(wks) do
		if prj.archivedirs then
			for _, dir in ipairs(prj.archivedirs) do
				if dir_list == nil then
					dir_list = ""
				else
					dir_list = (dir_list .. ', ')
				end
				dir_list = (dir_list .. '"' .. dir .. '"')
			end
		end
	end
			
	if dir_list then
		p.push('flatDir {')
		p.x('dirs %s', dir_list)
		p.pop('}') -- flat dir
	end
	
	p.pop('}') -- repositories
	p.pop('}') -- all projects
end

function m.generate_workspace_settings(wks)
	p.x('// auto-generated by premake-android-studio')
	for prj in workspace.eachproject(wks) do
		p.x('include ":%s"', prj.name)
		p.x('project(":%s").projectDir = file("%s/%s")', prj.name, prj.location, prj.name)
	end
end

function get_android_program_kind(premake_kind)
	local premake_to_android_kind =
	{
		["WindowedApp"] = "com.android.application",
		["ConsoleApp"] = "com.android.application",
		["StaticLib"] = "com.android.library",
		["SharedLib"] = "com.android.library",
	}
	return premake_to_android_kind[premake_kind]
end
	
function get_cmake_program_kind(premake_kind)
	local premake_to_cmake_kind =
	{
		-- native components of applications are shared libs
		["WindowedApp"] = "SHARED",
		["ConsoleApp"] = "SHARED",
		["SharedLib"] = "SHARED",
		["StaticLib"] = "STATIC"
	}
	return premake_to_cmake_kind[premake_kind]
end

function get_dir(file)
	return string.match(file, ".*/")
end

function m.generate_manifest(prj)
	-- look for a manifest in project files
	for cfg in project.eachconfig(prj) do		
		for _, file in ipairs(cfg.files) do
			if string.find(file, "AndroidManifest.xml") then
				-- copy contents of manifest and write with premake
				manifest = io.open(file, "r")
				xml = manifest:read("*a")
				manifest:close()
				p.w(xml)
				return
			end
		end
	end

	-- auto generate stub android manifest
	p.w('<?xml version="1.0" encoding="utf-8"?>')
	p.push('<manifest xmlns:android="http://schemas.android.com/apk/res/android"')
	p.x('package="lib.%s"', prj.name)
	p.w('android:versionCode="1"')
	p.w('android:versionName="1.0" >')
	p.w('<uses-sdk android:minSdkVersion="19" />')
	p.pop('<application/>')
	p.pop('</manifest>')
end
	
function m.add_sources(cfg, category, exts, excludes, strip)		
	-- get srcDirs because gradle experimental with jni does not support adding single files :(
	local dir_list = nil
	for _, file in ipairs(cfg.files) do
		skip = false
		for _, exclude in ipairs(excludes) do
			if string.find(file, exclude) then
				skip = true
				break
			end
		end
		if not skip then
			for _, ext in ipairs(exts) do
				file_ext = path.getextension(file)
				if file_ext == ext then
					if (dir_list == nil) then dir_list = ""
					else dir_list = (dir_list .. ', ') 
					end
					new_dir = get_dir(file)
					if strip then
						loc = string.find(new_dir, strip)
						if (loc) then
							new_dir = new_dir:sub(0, loc-1 + string.len(strip))
						end
					end
					dir_list = (dir_list .. '"' .. new_dir .. '"')
				end
			end
		end
	end
			
	if dir_list then 
		p.x((category .. '.srcDirs += [%s]'), dir_list)
	end
end

function m.csv_string_from_table(tab)
	csv_list = nil
	if tab then
		for _, v in ipairs(tab) do
			if csv_list == nil then
				csv_list = ""
			else
				csv_list = (csv_list .. ", ")
			end
			csv_list = (csv_list .. '"' .. v .. '"')
		end
	end
	return csv_list
end
	
function m.generate_cmake_lists(prj)
	p.w('cmake_minimum_required (VERSION 2.6)')
	
	cmake_file_exts =
	{
		".cpp",
		".c",
		".h",
		".hpp"	
	}
	
	local project_deps = ""
	
	-- include cmake dependencies
	for _, dep in ipairs(project.getdependencies(prj, "dependOnly")) do
		wks = prj.workspace
		for prj in workspace.eachproject(wks) do
			if prj.name == dep.name then
				cmakef = (prj.location .. "/" .. prj.name .. "/" .. "CMakeLists.txt")
				local f = io.open(cmakef,"r")
				if f ~= nil then 
					io.close(f)
					p.x('include(%s)', cmakef)
					project_deps = (project_deps .. " " .. prj.name)
				end
			end 
		end
	end
	
	p.x('project (%s)', prj.name)
	
	cmake_kind = get_cmake_program_kind(prj.kind)
	for cfg in project.eachconfig(prj) do				
		-- somehow gradle wants lowecase debug / release but 
		-- still passes "Debug" and "Release" to cmake
		p.x('if(CMAKE_BUILD_TYPE STREQUAL "%s")', cfg.name)
		-- target				
		local file_list = ""
		for _, file in ipairs(cfg.files) do
			for _, ext in ipairs(cmake_file_exts) do
				if path.getextension(file) == ext then
					file_list = (file_list .. " " .. file)
				end
			end
		end
		if file_list ~= "" then
			p.x('add_library(%s %s %s)', prj.name, cmake_kind, file_list)
		end
		
		-- include dirs
		local include_dirs = ""
		for _, dir in ipairs(cfg.includedirs) do
			include_dirs = (include_dirs .. " " .. dir)
		end
		if include_dirs ~= "" then
			p.x('target_include_directories(%s PUBLIC %s)', prj.name, include_dirs)
		end
		
		-- cpp flags
		local cpp_flags = ""
		for _, cppflag in ipairs(cfg.buildoptions) do
			cpp_flags = (cpp_flags .. " " .. cppflag)
		end
		
		--optimises
		local opt_map = { On = 3, Size = 's', Speed = 3, Full = 'fast', Debug = 1 }
		opt_level = opt_map[cfg.optimize] 
		if opt_level then
			opt_flag = ("-O" .. opt_level)
			cpp_flags = (cpp_flags .. " " .. opt_flag)
		end

		if cpp_flags ~= "" then
			p.x('target_compile_options(%s PUBLIC %s)', prj.name, cpp_flags)
		end
		
		-- ld flags
		local ld_flags = ""
		
		-- links
		for _, link in ipairs(config.getlinks(cfg, "system", "fullpath")) do
			ext = path.getextension(link)
			if ext ~= ".aar" and ext ~= ".jar" then
				ld_flags = (ld_flags .. " " .. link)
			end
		end
		
		-- project / dependency links
		if project_deps ~= "" then
			ld_flags = (ld_flags .. " " .. project_deps)
		end
		
		for _, ldflag in ipairs(cfg.linkoptions) do
			ld_flags = (ld_flags .. " " .. ldflag)
		end
		
		-- lib directories
		for _, libdir in ipairs(cfg.libdirs) do
			ld_flags = (ld_flags .. " -L" .. libdir)
		end
		
		if ld_flags ~= "" then
			p.x('target_link_libraries(%s %s)', prj.name, ld_flags)
		end
		
		-- defines
		local defines = ""
		for _, define in ipairs(cfg.defines) do
			defines = (defines .. " " .. define)
		end
		if defines ~= "" then
			p.x('target_compile_definitions(%s PUBLIC %s)', prj.name, defines)
		end
		
		p.w('endif()')
		
	end
end

function m.generate_project(prj)
	p.x('// auto-generated by premake-android-studio')
	p.x("apply plugin: '%s'", get_android_program_kind(prj.kind))
	
	p.push('android {')
	
	-- signing config for release builds
	p.push('signingConfigs {')
	p.push('config {')
	p.w("keyAlias 'key'")
	p.w("keyPassword 'password'")
	p.w("storePassword 'password'")
	p.w("storeFile file('android.jks')")
	p.pop('}') -- config
	p.pop('}') -- signingConfigs
	
	-- sdk / ndk etc
	if prj.androidsdkversion == nil then
		prj.androidsdkversion = "25"
	end
	if prj.androidminsdkversion == nil then
		prj.androidminsdkversion = "19"
	end		
	
	p.x('compileSdkVersion %s', prj.androidsdkversion)
	
	p.push('defaultConfig {')
	p.x('minSdkVersion %s', prj.androidminsdkversion)
	p.x('targetSdkVersion %s', prj.androidsdkversion)
	p.w('versionCode 1')
	p.w('versionName "1.0"')
	
	-- abis
	abi_list = m.csv_string_from_table(prj.androidabis)
	
	--[[
	if prj.androidabis then
		for _, abi in ipairs(prj.androidabis) do
			if abi_list == nil then
				abi_list = ""
			else
				abi_list = (abi_list .. ", ")
			end
			abi_list = (abi_list .. '"' .. abi .. '"')
		end
	end
	--]]
	
	p.pop('}') -- defaultConfig 
			
	p.push('buildTypes {')
	for cfg in project.eachconfig(prj) do
		p.push(string.lower(cfg.name) .. ' {')
		-- todo:
		-- p.w('signingConfig signingConfigs.config')
		if abi_list then
			p.push('ndk {')
			p.x('abiFilters %s', abi_list)
			p.pop('}')
		end
		p.pop('}') -- cfg.name
	end
	p.pop('}') -- build types
		
	-- cmake
	p.push('externalNativeBuild {')
	p.push('cmake {')
	p.w('path "CMakeLists.txt"')
	p.pop('}') -- cmake
	p.pop('}') -- externalNativeBuild
	
	p.push('sourceSets {')
	
	-- assets
	asset_dirs = m.csv_string_from_table(prj.assetdirs)

	if asset_dirs then
		p.push('main {')
		p.x('assets.srcDirs += [%s]', asset_dirs)
		p.pop('}')
	end
	
	-- java and resource files
	for cfg in project.eachconfig(prj) do
		p.push(string.lower(cfg.name) .. ' {')
		m.add_sources(cfg, 'java', {'.java'}, {})
		m.add_sources(cfg, 'res', {'.png', '.xml'}, {"AndroidManifest.xml"}, "/res/")
		p.pop('}') -- cfg.name
	end
	p.pop('}') -- sources
	
	-- lint options to avoid abort on error
	p.push('lintOptions {')
	p.w("abortOnError = false")
	p.pop('}')
	
	p.pop('}') -- android
			
	-- project dependencies, java links, etc
	p.push('dependencies {')
	
	-- aar / jar links
	for cfg in project.eachconfig(prj) do
		for _, link in ipairs(config.getlinks(cfg, "system", "fullpath")) do
			ext = path.getextension(link)
			if ext == ".aar" or ext == ".jar" then
				p.x("implementation (name:'%s', ext:'%s')", path.getbasename(link), ext:sub(2, 4))
			end
		end
		break
	end
	
	-- android dependencies
	if prj.androiddependencies then
		for _, dep in ipairs(prj.androiddependencies) do
			p.x("implementation '%s'", dep)
		end
	end
	
	-- project compile links
	for _, dep in ipairs(project.getdependencies(prj, "dependOnly")) do
		p.x("implementation project(':%s')", dep.name)
	end
	
	p.pop('}') -- dependencies
end

print("Premake: loaded module android-studio")

-- Return module interface
p.modules.android_studio = m
return m