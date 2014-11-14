require 'selenium-webdriver'
require 'faker'
require 'byebug'

def log(line)
  open('order_log.txt', 'a') do |f|
    f.puts line
  end
end

def read_log
  f = File.open('order_log.txt', "r")
  f.each_line do |line|
    puts line
  end
  f.close

end

def wait_for_enter(message="")
  puts message
  puts "Press Enter To Continue..."
  gets
end

class Selenium::WebDriver::Driver
  def find_dropdown(type, selector)
    el = self.find_element(type, selector)
    Selenium::WebDriver::Support::Select.new(el)
  end

  def wait_until_visible(type, selector, timeout=10)
    wait = Selenium::WebDriver::Wait.new(timeout: timeout)
    wait.until { self.find_element(type, selector) }
  end

  def wait_until_invisible(type, selector, timeout=5)
    wait = Selenium::WebDriver::Wait.new(timeout: timeout)
    wait.until { self.find_elements(type, selector).empty? }
  end


end

class LeapDriver < Selenium::WebDriver::Driver

  attr_accessor :user, :order, :ordered, :restaurant_url, :total_price

  def generate_user
    Faker::Config.locale = 'en-US'
    user =  {
      first_name: 'John',
      last_name: 'Smith',
      email: "naruto137+dinosaurs-#{Faker::Number.number(10)}@gmail.com",
      phone: {
        npa: Faker::PhoneNumber.area_code,
        co: Faker::PhoneNumber.exchange_code,
        line: Faker::PhoneNumber.subscriber_number
      },
      password: 'foobarfoobar1'
    }

    self.user = user
  end

  def signup
    generate_user

    self.navigate.to 'https://www.leapset.com/order/profile/create'

    # create account

    self.find_element(:id, 'account_email').send_keys user[:email]
    self.find_element(:id, 'account_phone1').send_keys user[:phone][:npa]
    self.find_element(:id, 'account_phone2').send_keys user[:phone][:co]
    self.find_element(:id, 'account_phone3').send_keys user[:phone][:line]
    self.find_element(:id, 'account_pwd').send_keys user[:password]
    self.find_element(:id, 'account_confirm_pwd').send_keys user[:password]
    self.find_element(:css, '.creat-acc').click

    # set user's name

    self.find_element(:id, 'custinfo_first_name').send_keys user[:first_name]
    self.find_element(:id, 'custinfo_last_name').send_keys user[:last_name]
    self.find_element(:id, 'id_link_save_changes').click
  end

  def find_item(item)
    order_el = self.find_elements(:class, 'meal-menu-des').find { |el|
      el.text.downcase.include? item.downcase
    }
  end

  def get_price(name)
    item = find_item(name)
    price_string = item.find_element(:xpath, "../div[@class='meal-menu-price']").text
    price = price_string.gsub("$", "").to_f
  end

  def find_cheapest_item
    item_prices = self.find_elements(:class, 'meal-menu-price').map { |el|
      price = el.text.gsub("$", "").to_f
      name = el.find_element(:xpath, "../div[@class='meal-menu-des']").text
      {name: name, price: price}
    }
    min = item_prices.min_by { |item| item[:price] }

    cheapest_item = min
  end

  def add_item(item, quantity, custom_instructions="")
    order_el = find_item(item)
    order_el.click

    # wait for modal to pop up
    
    self.wait_until_visible(:class, 'cust-txt-tp-1')

    # enter special instructions and add to cart!
    quantity_input = self.find_element(:id, 'id_add_item_dlg_quantity')
    quantity_input.clear
    quantity_input.send_keys(quantity)

    self.find_element(:class, 'cust-txt-tp-1').send_keys custom_instructions
    self.find_element(:class, 'add-item').click

    begin
      wait_until_invisible(:class, 'add-item')
    rescue
      wait_for_enter "Please choose your preferences and click the button to add"
    end
  end

  def read_items
    order = []

    num_rows = self.find_elements(:class, "row-main-product").length

    num_rows.times do |i|

      row = self.find_elements(:class, "row-main-product")[i]
      cols = row.find_elements(:css, "td")


      quantity = cols[0].text
      name = cols[1].text

      price = get_price(name)

      item = {
        quantity: cols[0].text,
        name: cols[1].text,
        price: price
      }

      order << item
    end

    return order
  end

  def go_to_menu
    self.navigate.to self.restaurant_url
  end

  def order_items
    self.total_price = 0
    cheapest_item = find_cheapest_item

    self.order = self.read_items

    log(Time.now.strftime("\n\n\n%A, %m/%d %H:%M"))
    log(self.restaurant_url)

    order.each do |item|

      item[:quantity].to_i.times do

        # byebug

        self.manage.delete_all_cookies
        # byebug

        self.signup
        # byebug

        self.go_to_menu
        # byebug
        
        self.add_item(item[:name], 1)
        # byebug

        if item[:price] < 5.01
          num_cheap_thing = ((5.01 - item[:price]) / cheapest_item[:price]).ceil
          add_item(cheapest_item[:name], num_cheap_thing)
        end

        self.checkout

        checkout_price_string = self.find_element(:id, "id_cart_total_amount_row").text
        checkout_price = checkout_price_string.gsub(/[^0-9\.]/, "").to_f

        log "#{item[:name]}\t$#{checkout_price}"
        self.total_price += checkout_price
      end


    end
    log "Total: #{self.total_price}"

    read_log
  end

  def checkout
    self.wait_until_visible(:xpath, '//*[@id="id_shopping_cart_checkout_form"]/ul/li[3]/input')

    # checkout
    self.find_element(:xpath, '//*[@id="id_shopping_cart_checkout_form"]/ul/li[3]/input').click
    self.find_element(:id, 'pickup_discount_code').send_keys '5OFF'

    self.find_element(:xpath, '//*[@id="id_pickup_form"]/div[8]/div/div/div[2]/a').click

    # billing info
    self.find_element(:id, 'payment_nameoncard').send_keys 'John Smith'
    self.find_element(:id, 'payment_ccnumber').send_keys ENV["AMEX_NUM"]
    self.find_dropdown(:id, 'payment_cctype').select_by(:text, 'American Express')
    self.find_dropdown(:id, 'payment_expdatem').select_by(:text, ENV["AMEX_MONTH"])
    self.find_dropdown(:id, 'payment_expdatey').select_by(:text, ENV["AMEX_YEAR"])
    self.find_element(:id, 'payment_cvvcode').send_keys ENV["AMEX_CVV"]

    wait_for_enter "Please confirm your order. Exit the program to cancel the order"

    # place the order! nom nom!
    # self.find_element(:class, 'submit-order-buttn').click

  end

end


f = LeapDriver.for :firefox

f.navigate.to "https://www.leapset.com/order/ca-san-francisco"

wait_for_enter "Order what you want!"

f.restaurant_url = f.current_url

# THIS IS WHERE YOU ORDER
# f.add_item("Avocado Shake", 2)
# f.add_item("Watermelon Lychee", 2)

# byebug

f.order_items