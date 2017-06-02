# 1. Надо загрузить все страницы. Или просто получать их и сразу парсить.
# 2. Надо сформировать хэш
# 3. Надо запилить всё это дело в csv и сохранить с двумя версиями разделителей
# Сначала загрузить страницу без параметров и дернуть оттуда список вариантов
# #pid0
# Затем построить запрос для каждого варианта, добавить параметр pco0
# При первой загрузке проверить, сколько страниц есть для каждого варианта
# Пройтись по страницам и, собственно, дёрнуть оттуда названия

# ! Надо парсить синонимы (готово)
# ! Надо алгоритм деления на род, вид и сорт

# Точное определение: (слово с большой буквы) пробел (слово) пробел (что-то
# начиная с кавычки)

# Ещё один вариант: (слово с большой буквы) пробел (слово) пробел (что-то
# начиная со слова из больших букв)

require 'rubygems'
require 'nokogiri'
require 'net/http'
require 'pry'
require 'csv'
require 'json'

# TODO: get LANG from command line
LANG = 3 # 1 - Polish, 2 - English, 3 - Russian

# Хэш для растений
plants = {}

advanced_search_page =
  Nokogiri::HTML Net::HTTP.get('www.zszp.pl', "/?id=215&lang=#{LANG}")

GROUP_SELECT_TAG = 'select#pid0'.freeze
FORM_SELECT_TAG = 'select#pid2'.freeze
SIGNIFICANT_OPTION_TAG = 'option.czarny'.freeze

advanced_search_page.search(GROUP_SELECT_TAG)
                    .search(SIGNIFICANT_OPTION_TAG).each do |group|
  plants[group.attributes['value'].value] =
    { name: group.inner_text, plants: [] }
end
# Теперь есть вот такой хэш. Можно идти по ключам и дополнять value
# {"3"=>{:name=>"вересковые"},
#  "4"=>{:name=>"лианы"},
#  "2"=>{:name=>"лиственные"},
#  "6"=>{:name=>"многолетники"},
#  "7"=>{:name=>"плодовые"},
#  "5"=>{:name=>"розы"},
#  "1"=>{:name=>"хвойные"}}

def page_content(group_id, page, form = '0')
  Nokogiri::HTML(
    Net::HTTP.get(
      'www.zszp.pl',
      "/?id=215&lang=#{LANG}&pco0=#{group_id}&pco2=#{form}&s=#{page}"
    )
  )
end

plants.each do |group_id, group|
  page = 1
  loop do
    current_page = page_content(group_id, page)
    puts "Group #{group_id}, page #{page}"
    elements = current_page.search('div.szukaj500')
    elements.each do |element|
      plant_name = element.text.match(/.+/)[0]
      synonims_match = element.text.match(/Synonimy: (.+)/)
      synonims = synonims_match ? synonims_match[1] : ''
      group[:plants] << { name: plant_name, form: '', synonims: synonims }
    end

    break if elements.count.zero?
    page += 1
  end
  # так я получил все растения группы. Теперь можно добить их формой
  # Получим страницу ещё разок
  page_for_forms = page_content(group_id, 1)
  # Спарсим оттуда все варианты форм
  page_for_forms.search(FORM_SELECT_TAG)
                .search(SIGNIFICANT_OPTION_TAG).each do |form|
    form_name = form.inner_text
    form_id = form.attributes['value'].value
    # Для каждой формы пробежимся по страницам
    page = 1
    loop do
      current_page = page_content(group_id, page, form_id)
      puts "Group #{group_id}, page #{page}, form #{form_id}"
      elements = current_page.search('div.szukaj500')
      elements.each do |element|
        found_plant = element.text.match(/.+/)[0]
        # Пройдём по найденным растениям, ищем их в plants и добавляем текущую
        # группу
        group[:plants].each do |plant|
          next unless plant[:name] == found_plant
          plant[:form] = form_name
          puts "#{plant[:name]} is #{plant[:form]}"
          break
        end
      end

      break if elements.count.zero?
      page += 1
    end
  end
end

def parse_plant_name(name)
  kind = ''
  view = ''
  grade = ''
  additional_info = ''

  sort_match = name.match(/^([^']+)?('(.+)')?([^']+)?$/)

  beginning = sort_match[1] if sort_match
  grade = sort_match[3] if sort_match
  ending = sort_match[4] if sort_match

  # Раскидываемся с началом, там точно есть род, если что-то ещё - это вид
  if beginning
    beginning_match = beginning.match(/^[\s ]*([+×]?[A-Z]\S+)[\s ]+(.+\S)?[\s ]*$/)
    if beginning_match
      kind = beginning_match[1]
      view = beginning_match[2]
    end
  end

  additional_info = ending.match(/^[\s ]*(\S(.*\S)?)?[\s ]*$/)[1] if ending

  { kind: kind, view: view, grade: grade, additional_info: additional_info }
end

plants_array = []
plants.each do |_group_id, group|
  group[:plants].each do |plant|
    parsed = parse_plant_name(plant[:name])
    synonims = []
    plant[:synonims].split(',').each do |synonim|
      parsed_synonim = parse_plant_name(synonim)[:grade]
      if parsed_synonim && parsed_synonim != parsed[:grade]
        synonims << parsed_synonim
      end
    end
    plants_array << "#{group[:name]};;$#{plant[:form]};;$#{parsed[:kind]};;$" \
                    "#{parsed[:view]};;$#{parsed[:grade]};;$" \
                    "#{parsed[:additional_info]};;$#{synonims.join(', ')}"

  end
end

File.open('plants_array', 'w') do |f|
  f.write(plants_array.join("\n"))
end

plants_array = []
File.open('plants_array', 'r') do |file|
  while (line = file.gets)
    plants_array << line
  end
end

plants_hash = {}
plants_array.each do |plant|
  plant_match = plant.match(/^([^;$]*);;\$([^;$]*);;\$([^;$]*);;\$([^;$]*);;\$([^;$]*);;\$([^;$]*);;\$([^;$]*)$/)
  group = plant_match[1]
  form = plant_match[2]
  kind = plant_match[3]
  view = plant_match[4]
  grade = plant_match[5]
  additional_info = plant_match[6]
  synonims = plant_match[7]

  plants_hash[group] = {} unless plants_hash[group]
  plants_hash[group][form] = {} unless plants_hash[group][form]
  plants_hash[group][form][kind] = {} unless plants_hash[group][form][kind]
  plants_hash[group][form][kind][view] = {} unless plants_hash[group][form][kind][view]
  plants_hash[group][form][kind][view][grade] = {} unless plants_hash[group][form][kind][view][grade]
  plants_hash[group][form][kind][view][grade][:additional_info] = additional_info
  plants_hash[group][form][kind][view][grade][:synonims] = synonims
end

CSV.open("plants_#{Time.now.to_i}.csv", 'wb') do |csv|
  csv << ['Группа', 'Форма', 'Род', 'Вид', 'Сорт', 'Дополнительная информация',
          'Синонимы']
  plants_hash.each do |group_name, group|
    group.each do |form_name, form|
      form.each do |kind_name, kind|
        # Род на отдельной строке
        csv << [group_name, form_name, kind_name]
        kind.each do |view_name, view|
          # Вид на отдельной строке
          csv << [group_name, form_name, kind_name, view_name]
          view.each do |grade_name, grade|
            unless grade.empty?
              csv << [group_name, form_name, kind_name, view_name, grade_name,
                      grade[:additional_info], grade[:synonims]]
            end
          end
        end
      end
    end
  end
end
