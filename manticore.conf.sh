#!/bin/bash

if [[ $(grep -e "#!\/bin\/sh" -e "#!\/bin\/bash" /etc/manticoresearch/manticore.conf) ]]; then
  executableConfig=1
fi

if [ -z $executableConfig ]; then
  conf=$(cat /etc/manticoresearch/manticore.conf)
else
  conf=$(bash /etc/manticoresearch/manticore.conf)
fi

if [ -z "$searchd_listen" ]; then
  confHash=$(md5sum /etc/manticoresearch/manticore.conf | awk '{print $1}')
  expectedConfHash=$(cat /manticore.conf.md5)

  if [[ "$confHash" == "$expectedConfHash" ]]; then
    export searchd_listen='9306:mysql41|/var/run/mysqld/mysqld.sock:mysql41|9308:http|$ip:9312|$ip:9315-9325:replication'
  fi
fi

# Function to update a setting within a specific section block
# Usage: update_setting_in_section "section_identifier" "setting_key" "setting_value"
# section_identifier can be "searchd", "common", "source min", "table abc", etc.
update_setting_in_section() {
  local section_identifier="$1"
  local setting_key="$2"
  local setting_value="$3"
  
  # Convert underscores in section_identifier to spaces for matching
  # This allows "source_min" in env var to match "source min" in config
  local section_pattern=$(echo "$section_identifier" | sed 's/_/[[:space:]]\+/g')
  local section_start_pattern="^[[:space:]]*${section_pattern}[[:space:]]*\{"
  
  # Check if section exists
  if ! echo "$conf" | grep -qE "$section_start_pattern"; then
    # Section doesn't exist, create it
    # Convert underscores back to spaces for the actual section declaration
    local section_name=$(echo "$section_identifier" | sed 's/_/ /g')
    conf="${conf}
${section_name} {
    ${setting_key} = ${setting_value}
}"
    return
  fi
  
  # Section exists, use awk to process and update within that section only
  # This properly handles nested blocks and only modifies settings within the target section
  conf=$(echo "$conf" | awk -v section_start_pattern="$section_start_pattern" \
                            -v setting_key="$setting_key" \
                            -v setting_value="$setting_value" '
  BEGIN {
    in_target_section = 0
    section_depth = 0
    found_setting = 0
  }
  {
    line = $0
    original_line = line
    
    # Check if we are entering the target section
    if (match(line, section_start_pattern)) {
      in_target_section = 1
      section_depth = 1
      print line
      next
    }
    
    # If we are in the target section, track depth for nested blocks
    if (in_target_section == 1) {
      # Count opening and closing braces on this line
      open_braces = 0
      close_braces = 0
      len = length(original_line)
      for (i = 1; i <= len; i++) {
        char = substr(original_line, i, 1)
        if (char == "{") open_braces++
        if (char == "}") close_braces++
      }
      section_depth += (open_braces - close_braces)
      
      # Check if we have left the target section
      if (section_depth <= 0) {
        # Add setting before closing brace if not found
        if (found_setting == 0) {
          # Get indentation from closing brace line
          match(original_line, /^[[:space:]]*/)
          indent = substr(original_line, 1, RLENGTH)
          print indent "    " setting_key " = " setting_value
        }
        in_target_section = 0
        found_setting = 0
        section_depth = 0
        print original_line
        next
      }
      
      # Check if this line contains the setting we want to update (within the section)
      if (match(original_line, "^[[:space:]]*" setting_key "[[:space:]]*=")) {
        # Replace the setting value, preserve indentation
        match(original_line, /^[[:space:]]*/)
        indent = substr(original_line, 1, RLENGTH)
        print indent setting_key " = " setting_value
        found_setting = 1
        next
      }
    }
    
    print original_line
  }
  ')
}

# Check for searchd/common env vars (backward compatibility)
while IFS='=' read -r envVariable value; do
  if [[ "${envVariable}" == searchd_* ]]; then
    hasSearchdEnv=1
  elif [[ "${envVariable}" == common_* ]]; then
    hasCommonEnv=1
  fi
done < <(env)

# Create searchd/common sections if they don't exist and env vars are present
if [[ -n $hasCommonEnv && ! $(echo $conf | grep -E "common\s*{") ]]; then
    conf="$(echo "${conf}")
common {
}"
fi

if [[ -n $hasSearchdEnv && ! $(echo $conf | grep -E "searchd\s*{") ]]; then
    conf="$(echo "${conf}")
searchd {
}"
fi

if hostname -I > /dev/null 2>&1; then
  hostip=$(hostname -I|cut -d\  -f 1)
elif hostname -i > /dev/null 2>&1; then
  hostip=$(hostname -i|rev|cut -d\  -f 1|rev)
else
  hostip="0.0.0.0"
fi

# Process all environment variables
while IFS='=' read -r envVariable value; do
  
  # Skip if not a config variable (doesn't contain underscore)
  if [[ ! "${envVariable}" =~ _ ]]; then
    continue
  fi
  
  # Split on the last underscore to get section_identifier and setting_name
  # This handles: searchd_setting, common_setting, source_min_sql_user, table_abc_path, etc.
  # Extract section identifier (everything before last underscore) and setting name (after last underscore)
  # Use parameter expansion: ${var%_*} removes last _ and everything after, ${var##*_} removes everything up to last _
  local section_identifier="${envVariable%_*}"
  local setting_name="${envVariable##*_}"
  
  # Safety check: if no underscore was found, section_identifier would be the same as envVariable
  if [ "$section_identifier" == "$envVariable" ]; then
    continue
  fi
  
  # Get the actual value and escape it
  actual_value=$(echo ${!envVariable} | sed 's/\//\\\//g')
  
  # Special handling for searchd listen directive
  # The listen directive is special because:
  # 1. It can appear multiple times in the searchd section (each becomes a separate "listen = ..." line)
  # 2. Values are pipe-separated (|) and need to be split into multiple lines
  # 3. The $ip variable needs to be expanded to the actual host IP
  # 4. All existing listen directives in the searchd section should be replaced (not just updated)
  if [[ "$section_identifier" == "searchd" && "$setting_name" == 'listen' ]]; then
    # Remove all existing listen directives only from the searchd section
    conf=$(echo "$conf" | awk '
      BEGIN { in_searchd = 0; section_depth = 0 }
      /^[[:space:]]*searchd[[:space:]]*\{/ { in_searchd = 1; section_depth = 1; print; next }
      in_searchd == 1 {
        # Count braces to track section depth
        temp = $0
        open_braces = gsub(/{/, "&", temp)
        temp = $0
        close_braces = gsub(/}/, "&", temp)
        section_depth += (open_braces - close_braces)
        
        # Skip listen directives within searchd section
        if (match($0, /^[[:space:]]*listen[[:space:]]*=/)) {
          if (section_depth > 0) {
            next  # Skip this line
          }
        }
        
        if (section_depth <= 0) {
          in_searchd = 0
        }
      }
      { print }
    ')
    
    # Parse pipe-separated values and expand $ip variable
    IFS='|' read -ra LISTEN_VALUES <<<"$actual_value"
    count=0
    actual_value=""

    for i in "${LISTEN_VALUES[@]}"; do
      i=${i/\$ip/$hostip}
      if [[ $count == 0 ]]; then
        actual_value=$i
      else
        actual_value="$actual_value\n    listen = $i"
      fi
      count=$((count + 1))
    done
  fi
  
  # Update the setting in the appropriate section
  update_setting_in_section "$section_identifier" "$setting_name" "$actual_value"

done < <(env)

echo "${conf}" > /etc/manticoresearch/manticore.conf.debug
echo "${conf}"
