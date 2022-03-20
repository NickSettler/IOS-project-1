#!/usr/bin/env bash

# csv structure: id,datum,vek,pohlavi,kraj_nuts_kod,okres_lau_kod,nakaza_v_zahranici,nakaza_zeme_csu_kod,reportovano_khs

AFTER_DATE=
BEFORE_DATE=
GENDER=
COMMAND=
FILES=
GZ_ENABLED=0
GZ_FILES=

ALLOWED_COMMANDS=("infected" "merge" "gender" "age" "daily" "monthly" "yearly" "countries" "districts" "regions")
ALLOWED_GENDERS=("M" "Z")
AGE_GROUPS=("0-5" "6-15" "16-25" "26-35" "36-45" "46-55" "56-65" "66-75" "76-85" "86-95" "96-105" "105-1000")

usage() {
  echo "Usage: $0 [-h] [FILTERS] [COMMAND] [LOG [LOG2 [...]]"
  echo "  -h      display this help and exit"
  echo "  FILTERS are one or more of:"
  echo "    -a DATETIME  use data after date"
  echo "    -b DATETIME  use data before date"
  echo "    -g GENDER    use data with gender [Z/M]"
  echo "  COMMAND is one of:"
  echo "    infected     count the number of infected people"
  echo "    merge        merge some files to one"
  echo "    gender       print statistics about infected people grouping by gender"
  echo "    age          print statistics about infected people grouping by age"
  echo "    daily        print statistics about infected people grouping by day"
  echo "    monthly      print statistics about infected people grouping by month"
  echo "    yearly       print statistics about infected people grouping by year"
  echo "    countries    print statistics about infected people grouping by country"
  echo "    districts    print statistics about infected people grouping by district"
  echo "    regions      print statistics about infected people grouping by region"
}

contains() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  -a)
    AFTER_DATE="$2"
    shift 2
    ;;
  -b)
    BEFORE_DATE="$2"
    shift 2
    ;;
  -g)
    GENDER="$2"
    shift 2
    ;;
  *)
    # check if command is allowed and set it
    if contains "$1" "${ALLOWED_COMMANDS[@]}"; then
      COMMAND="$1"
      shift
    fi

    if [ -z "$1" ]; then
      FILES+=("/dev/stdin")
    else
      while :; do
        if [ -f "$1" ]; then
          if [[ "$1" =~ \.gz$ ]]; then
            GZ_ENABLED=1
            GZ_FILES+=("$1")
          else
            FILES+=("$1")
          fi
        fi
        shift

        if [ -z "$1" ]; then
          break
        fi
      done
    fi
    ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]] && [[ "${GZ_ENABLED}" -eq 0 ]]; then
  FILES+=("/dev/stdin")
fi

if [ "$(gdate -d "$AFTER_DATE" +%s)" -gt "$(gdate -d "$BEFORE_DATE" +%s)" ]; then
  echo 'Before date must be before after date' >&2
  exit 1
fi

if [ -n "$GENDER" ]; then
  if ! contains "${GENDER}" "${ALLOWED_GENDERS[@]}"; then
    usage
    exit 0
  fi
fi

if [ "${GZ_ENABLED}" -eq 1 ]; then
  echo "GZ_FILES: ${GZ_FILES[*]}"
fi
echo "FILES: ${FILES[*]}"
echo "COMMAND: ${COMMAND}"
echo "AFTER_DATE: ${AFTER_DATE}"
echo "BEFORE_DATE: ${BEFORE_DATE}"
echo "GENDER: ${GENDER}"

process_files() {
  local line data

  for FILE in "${FILES[@]}"; do
    FILE="$(echo "$FILE" | xargs)"
    if [[ -n "$FILE" ]]; then
      {
        read -r line
        while read -r line || [ -n "$line" ]; do
          data="$(printf "%s\n%s" "$data" "$line")"
        done
      } <"$FILE"
    fi
  done

  echo "$data"
}

filter_data() {
  local data="$1"

  data=$(echo "$data" | awk -F "," -v after="$AFTER_DATE" '{if(after != ""){if(after <= $2){print}}else{print}}')
  data=$(echo "$data" | awk -F "," -v before="$BEFORE_DATE" '{if(before != ""){if(before >= $2){print}}else{print}}')
  data=$(echo "$data" | awk -F "," -v gender="$GENDER" '{if(gender != ""){if(gender == $4){print}}else{print}}')
  echo "$data"
}

validate_data() {
  local data="$1"

#  if ! gdate "+YYYY-MM-DD" -d "2000-11-14" >/dev/null 2>&1; then
#    echo "ER"
#  fi
#
#  awk -F "," '{print $2}' <<<"$data" | sed -e '//'
}

process_infected() {
  local data="$1"

  awk -F "," 'END{print NR}' <<<"$data"
}

process_gender() {
  local data="$1"

  awk -F "," '{print $4}' <<<"$data" | sort | uniq -c | awk -F " " '{print $2": " $1}'
}

process_age() {
  local min_age max_age count data="$1"

  for i in "${AGE_GROUPS[@]}"; do
    min_age=$(awk -F "-" '{print $1}' <<<"$i")
    max_age=$(awk -F "-" '{print $2}' <<<"$i")

    count=$(awk -F "," -v min_age="$min_age" -v max_age="$max_age" \
      '{if($3 != ""){if($3 >= min_age && $3 <= max_age){print}}}' <<<"$data" | awk "END{print NR}")

    if [ "$i" != "105-1000" ]; then
      awk -F " " "{printf \"%-6s: %s\n\", \"$i\", \$1}" <<<"$count"
    else
      awk -F " " "{printf \"%-6s: %s\n\", \">105\", \$1}" <<<"$count"
    fi
  done

  awk -F "," '{if($3 == ""){print "None"}}' <<<"$data" | uniq -c | awk -F " " '{print "None  : " $1}'
}

process_daily() {
  local data="$1"

  wc -l <<<"$data"
}

process_monthly() {
  local data="$1"

  echo "$data" | awk -F "," '{print $2}' | sort | sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})/\1-\2/g' |
    uniq -c | awk -F " " '{print $2": " $1}'
}

process_yearly() {
  local data="$1"

  echo "$data" | awk -F "," '{print $2}' | sort | sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})/\1/g' |
    uniq -c | awk -F " " '{print $2": " $1}'
}

process_countries() {
  local data="$1"

  awk -F "," '{if($8 != ""){if($8 != "CZ"){print $8}}else{print "None"}}' <<<"$data" |
    sort | uniq -c | awk -F " " '{print $2": " $1}'
}

process_districts() {
  local data="$1"

  awk -F "," '{if($6 != ""){print $6}else{print "None"}}' <<<"$data" |
    sort | uniq -c | awk -F " " '{print $2": " $1}'
}

process_regions() {
  local data="$1"

  awk -F "," '{if($5 != ""){print $5}else{print "None"}}' <<<"$data" |
    sort | uniq -c | awk -F " " '{print $2": " $1}'
}

csv_array="$(process_files)"
csv_array="$(filter_data "$csv_array")"
#validate_data "$csv_array"
#process_infected "$csv_array"
#process_gender "$csv_array"
#process_age "$csv_array"
#process_daily "$csv_array"
#process_monthly "$csv_array"
#process_yearly "$csv_array"
#process_countries "$csv_array"
#process_districts "$csv_array"
#process_regions "$csv_array"
