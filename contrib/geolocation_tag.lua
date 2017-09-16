--[[
    This file is part of darktable,
    copyright (c) 2017 Jannis_V

    darktable is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    darktable is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    You should have received a copy of the GNU General Public License
    along with darktable.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[
This script adds following location information to tags of selected images using the google geocoding API
- country
- administrative_area_level_1
- locality
	
A configureable prefix is added to each tag, e.g. location| => (location|germany)
The language of the tags can be configured using codes from
https://developers.google.com/maps/faq?hl=de#languagesupport
]]

local dt = require "darktable"
local df = require "lib/dtutils.file"
local gettext = dt.gettext

dt.configuration.check_version(...,{3,0,0},{4,0,0},{5,0,0})

-- Tell gettext where to find the .mo file translating messages for a particular domain
gettext.bindtextdomain("geolocation_tag",dt.configuration.config_dir.."/lua/locale/")

local function _(msgid)
  return gettext.dgettext("geolocation_tag", msgid)
end

local function stop_job(job)
  job.valid = false
end

local locations = {}

local function add_geolocation_tags()

  if not df.check_if_bin_exists("curl") then
    dt.print(_("curl is not installed"))
    print(_("curl is not installed"))
    return
  end
  
  if not df.check_if_bin_exists("jq") then
    dt.print(_("jq is not installed"))
    print(_("jq is not installed"))
    return
  end

  local job = dt.gui.create_job(_("applying geolocation tags"), true, stop_job)

  local sel_images = dt.gui.action_images
    
  for key,image in ipairs(sel_images) do
    if(job.valid) then
      job.percent = (key-1)/#sel_images
      if ((image.longitude and image.latitude) and
        (image.longitude ~= 0 and image.latitude ~= 90) -- Just in case
      ) then
      
        local lat = string.gsub(image.latitude,',','.')
        local lon = string.gsub(image.longitude,',','.')
        local lines = {}
                        
        if locations[lat.." "..lon] == nil then
        -- Use geometric center or approximate, higher accuracy seems to force an address for remote locations by using places of other cities close by
          local command = string.format("curl --silent \"https://maps.googleapis.com/maps/api/geocode/json?latlng=%s,%s&language=%s\" | jq -r '.status, (.results[] | select(.geometry.location_type == \"GEOMETRIC_CENTER\" or .geometry.location_type == \"APPROXIMATE\") | .address_components[] | select(.types[0] == \"country\" or .types[0] == \"administrative_area_level_1\" or .types[0] == \"locality\") | .long_name)' | head -n 4",
		    lat,lon,dt.preferences.read("geolocation_tag","language","string"))
          local handle = io.popen(command)
          local result = handle:read("*a")
          for line in result:gmatch("[^\n]+") do
            table.insert(lines,line)
		  end
		  handle:close()
		  -- Only save location if it is valid
		  if #lines == 4 and lines[1] == "OK" then
		    locations[lat.." "..lon] = lines
		  end
        else
          print(_("location has already been queried"))
          lines = locations[lat.." "..lon]
        end
        if #lines == 0 then
          dt.print(_("No response from API"))
          print(_("No response from API"))
          break
        end
        if #lines == 4 and lines[1] == "OK" then
          print(image.filename..": "..lat..","..lon.." "..lines[2]..", "..lines[3]..", "..lines[4])
          for i = 2,4 do
            if lines[i] ~= "null" then
              local tagname = lines[i]
              local prefix = dt.preferences.read("geolocation_tag","prefix","string")
              if #prefix > 0 then
                tagname = prefix..tagname
              end
              local tag = dt.tags.create(tagname)
              dt.tags.attach(tag,image)
            end
          end
        elseif lines[1] == "OVER_QUERY_LIMIT" then
          dt.print(_("API query limit reached, aborting"))
          print(_("API query limit reached, aborting"))
          break
        end
      end
      else
        break
    end
  end
  job.valid = false
end

dt.preferences.register("geolocation_tag","language","string",_("geolocation tag language"),_("code as stated in https://developers.google.com/maps/faq?hl=de#languagesupport"),"en")
dt.preferences.register("geolocation_tag","prefix","string",_("geolocation tag prefix"),_("a prefix to add to the auto generated tags, e.g. place|"),"place|")

dt.gui.libs.image.register_action(_("add geolocation tags"),add_geolocation_tags,_("add tags with city, state and country to images with geotag"))
