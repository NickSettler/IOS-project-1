#!/usr/bin/env bash

# csv structure: id,datum,vek,pohlavi,kraj_nuts_kod,okres_lau_kod,nakaza_v_zahranici,nakaza_zeme_csu_kod,reportovano_khs

AFTER_DATE=
BEFORE_DATE=
GENDER=
COMMAND="merge"
FILES=()
GZ_ENABLED=0
GZ_FILES=()
HISTOGRAM_ENABLED=0
HISTOGRAM_WIDTH=

ALLOWED_COMMANDS=("infected" "merge" "gender" "age" "daily" "monthly" "yearly" "countries" "districts" "regions")
HISTOGRAM_COMMANDS=(  "gender"  "age" "daily" "monthly" "yearly"  "countries" "districts" "regions")
HISTOGRAM_WIDTHS=(    100000    10000 500     10000     100000    100         1000        10000)
ALLOWED_GENDERS=("M" "Z")
AGE_GROUPS=("0-5" "6-15" "16-25" "26-35" "36-45" "46-55" "56-65" "66-75" "76-85" "86-95" "96-105" "105-1000")

HEADER="id,datum,vek,pohlavi,kraj_nuts_kod,okres_lau_kod,nakaza_v_zahranici,nakaza_zeme_csu_kod,reportovano_khs"

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

index() {
  local i=0
  for element in "${@:2}"; do
    [[ "$element" == "$1" ]] && echo "$i" && return
    ((i++))
  done
  echo -1
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
  -s)
    HISTOGRAM_ENABLED=1
    if [[ $2 =~ [0-9]+$ ]]; then
      HISTOGRAM_WIDTH=$2
      shift 2
    else
      shift
    fi
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
          if [[ "$1" =~ \.gz$ || "$1" =~ \.bz2$ ]]; then
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

#if [ "${GZ_ENABLED}" -eq 1 ]; then
#  echo "GZ_FILES: ${GZ_FILES[*]}"
#fi
#echo "FILES: ${FILES[*]}"
#echo "COMMAND: ${COMMAND}"
#echo "AFTER_DATE: ${AFTER_DATE}"
#echo "BEFORE_DATE: ${BEFORE_DATE}"
#echo "GENDER: ${GENDER}"
#echo "HISTOGRAM: ${HISTOGRAM_ENABLED}"
#echo "WIDTH: ${HISTOGRAM_WIDTH}"

process_files() {
  local filename extension data=""

  for FILE in "${FILES[@]}"; do
    data+=$(cat "$FILE" | tail -n +2)
    data+=$'\n'
  done

  if [[ "$GZ_ENABLED" -eq 1 ]]; then
    for FILE in "${GZ_FILES[@]}"; do
      filename=$(basename "$FILE")
      extension="${filename##*.}"

      if [[ "$extension" == "gz" ]]; then
        data+=$(cat "$FILE" | gzip -d | tail -n +2)
      elif [[ "$extension" == "bz2" ]]; then
        data+=$(cat "$FILE" | bzip2 -d | tail -n +2)
      fi
      data+=$'\n'
    done
  fi

  echo "$data"
}

validate_data() {
  local date age data="$1"

  data=$(echo "$data" | sed -r '/^\s*$/d')
  data=$(echo "$data" | awk -F '[[:blank:]]*,[[:blank:]]*' -v OFS=, '{gsub(/^[[:blank:]]+|[[:blank:]]+$/, ""); $1=$1} 1')

  for line in $data; do
    date="$(echo "$line" | awk -F ',' '{print $2}')"
    age="$(echo "$line" | awk -F ',' '{print $3}' | bc -l)"

    if ! gdate "+%Y-%m-%d" -d "$date" >/dev/null 2>&1; then
      echo "Invalid date: $line" >&2
    elif (( $(echo "$age < 0" | bc -l) )); then
      echo "Invalid age: $line" >&2
    else
      echo "$line"
    fi
  done
}

filter_data() {
  local data="$1"

  data=$(echo "$data" | awk -F "," -v after="$AFTER_DATE" '{if(after != ""){if(after <= $2){print}}else{print}}')
  data=$(echo "$data" | awk -F "," -v before="$BEFORE_DATE" '{if(before != ""){if(before >= $2){print}}else{print}}')
  data=$(echo "$data" | awk -F "," -v gender="$GENDER" '{if(gender != ""){if(gender == $4){print}}else{print}}')
  echo "$data"
}

run_command() {
  local data="$1"

  if [[ -n "$COMMAND" ]]; then
    case "$COMMAND" in
    infected)
      process_infected "$data"
      ;;
    merge)
      process_merge "$data"
      ;;
    gender)
      process_gender "$data"
      ;;
    age)
      process_age "$data"
      ;;
    daily)
      process_daily "$data"
      ;;
    monthly)
      process_monthly "$data"
      ;;
    yearly)
      process_yearly "$data"
      ;;
    countries)
      process_countries "$data"
      ;;
    districts)
      process_districts "$data"
      ;;
    regions)
      process_regions "$data"
      ;;
    esac
  fi
}

process_histogram() {
  local max max_signs sign_value data="$1"

  if ! contains "$COMMAND" "${HISTOGRAM_COMMANDS[@]}"; then
    echo "$data"
    return
  fi

  max=$(echo "$data" | awk -F ':' '{print $2}' | sort -n | tail -n 1)
  sign_value="${HISTOGRAM_WIDTHS[$(index "$COMMAND" "${HISTOGRAM_COMMANDS[@]}")]}"

  if [[ -n "$HISTOGRAM_WIDTH" ]]; then
    sign_value=$(echo "($max / $HISTOGRAM_WIDTH) / 1" | bc)
  fi

  max_signs=$(echo "($max / $sign_value) / 1" | bc)

  echo "$data" | awk -F ": " -v sign="$sign_value" -v m="$max_signs" 'BEGIN { s=sprintf(sprintf("%%%ds", m),""); gsub(/ /,"#",s) }
    {
      if (sign == 0)
        printf("%s:\n", $1);
     else
        printf("%s: %.*s\n", $1, int($2/sign), s);
    }'
}


process_infected() {
  local data="$1"

  awk -F "," 'END{print NR}' <<<"$data"
}

process_merge() {
  local data="$1"

  echo "$HEADER"
  echo "$data"
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

  echo "$data" | awk -F "," '{print $2}' | sort | sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})/\1-\2-\3/g' |
    uniq -c | awk -F " " '{print $2": " $1}'
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
csv_array="$(validate_data "$csv_array")"
csv_array="$(filter_data "$csv_array")"
csv_array="$(run_command "$csv_array")"
if [[ "$HISTOGRAM_ENABLED" -eq 1 ]]; then
  csv_array="$(process_histogram "$csv_array")"
fi
echo "$csv_array"