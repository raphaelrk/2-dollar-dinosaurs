class LeapDriver < Selenium::WebDriver::Driver
  attr_accessor :user, :order, :ordered, :restaurant_url, :total_price

  def go_to_menu
    self.navigate.to self.restaurant_url
  end

  def login(email, password)
    self.navigate.to 'https://www.leapset.com/order/login'
    self.find_element(:id, 'signin_email').send_keys email
    self.find_element(:id, 'signin_pwd').send_keys password
    self.find_element(:class, 'signin-buttn').click
  end

  def logout
    self.navigate.to 'https://www.leapset.com/order/logout'
  end

  def update_phone(x, y, z)
    self.navigate.to 'https://www.leapset.com/order/profile'

    self.find_element(:id, 'custinfo_phone1').clear
    self.find_element(:id, 'custinfo_phone2').clear
    self.find_element(:id, 'custinfo_phone3').clear

    self.find_element(:id, 'custinfo_phone1').send_keys x
    self.find_element(:id, 'custinfo_phone2').send_keys y
    self.find_element(:id, 'custinfo_phone3').send_keys z
    
    self.find_element(:id, 'id_link_save_changes').click
  end

  def signup(user)
    self.navigate.to 'https://www.leapset.com/order/profile/create'

    # create account
    self.find_element(:id, 'account_email').send_keys user[:email]
    $firebase.push("twilio-allocated-emails", user[:email])

    self.find_element(:id, 'account_phone1').send_keys user[:phone][:npa]
    self.find_element(:id, 'account_phone2').send_keys user[:phone][:co]
    self.find_element(:id, 'account_phone3').send_keys user[:phone][:line]
    self.find_element(:id, 'account_pwd').send_keys user[:password]
    self.find_element(:id, 'account_confirm_pwd').send_keys user[:password]
    self.find_element(:css, '.creat-acc').click

    log("using email: " + user[:email])
    log("using phone: " + "#{user[:phone][:npa]}-#{user[:phone][:co]}-#{user[:phone][:line]}")


    self.wait_until_visible(:id, 'custinfo_first_name')

    # set user's name
    self.find_element(:id, 'custinfo_first_name').send_keys user[:first_name]
    self.find_element(:id, 'custinfo_last_name').send_keys user[:last_name]
    self.find_element(:id, 'id_link_save_changes').click
  end

  def find_item(item)
    self.wait_until_visible(:class, "meal-menu-des")
    self.find_elements(:class, 'meal-menu-des').find { |el|
      el.text.downcase.include? item.downcase
    }
  end

  def get_price(name)
    item = find_item(name)
    price_string = item.find_element(:xpath, "../div[@class='meal-menu-price']").text
    price_string.gsub('$', '').to_f
  end

  def find_cheapest_item
    item_prices = self.find_elements(:class, 'meal-menu-price').map { |el|
      price = el.text.gsub('$', '').to_f
      name = el.find_element(:xpath, "../div[@class='meal-menu-des']").text
      {name: name, price: price}
    }
    item_prices.reject! { |item| item[:price] == 0.00 }
    item_prices.min_by { |item| item[:price] }
  end

  def add_item(item, quantity, custom_instructions='')
    order_el = find_item(item)
    order_el.click

    # wait for modal to pop up
    
    self.wait_until_visible(:class, 'cust-txt-tp-1')

    # enter special instructions and add to cart!
    quantity_input = self.find_element(:id, 'id_add_item_dlg_quantity')
    quantity_input.clear
    quantity_input.send_keys(quantity)

    self.find_element(:class, 'cust-txt-tp-1').send_keys custom_instructions

    if is_flag_on? "--custom"
      wait_for_enter 'Please choose your preferences and click the button to add'

    else
      self.find_element(:class, 'add-item').click

      begin
        wait_until_invisible(:class, 'add-item')
      rescue
        wait_for_enter 'Please choose your preferences and click the button to add'
      end
    end
    
  end

  def read_items
    order = []

    num_rows = self.find_elements(:class, 'row-main-product').length

    num_rows.times do |i|
      row = self.find_elements(:class, 'row-main-product')[i]
      cols = row.find_elements(:css, 'td')


      next_row_els = row.find_elements(:xpath, 'following-sibling::tr')

      custom = ""
      if next_row_els.empty?
        # there is no custom instrutions
      else
        next_row_el = next_row_els.first
        next_row_class = next_row_el.attribute("class")
    
        if next_row_class == "row-main-product-attrib"
          custom = next_row_el.text
        end
      end

      name = cols[1].text

      item = {
        quantity: cols[0].text,
        name: name,
        price: get_price(name),
        custom: custom
      }

      order << item
    end

    return order
  end

  def order_items
    self.total_price = 0
    cheapest_item = find_cheapest_item

    self.order = self.read_items

    3.times { log "" }
    log(Time.now.strftime('%A, %m/%d %H:%M'))
    log(self.restaurant_url)
    sentence = "Hi! So I already placed and paid for a to-go order here for "

    order_number = 0

    self.order.each do |item|
      item[:quantity].to_i.times do
        self.manage.delete_all_cookies
        self.user = generate_user(order_number)



        self.signup self.user
        self.go_to_menu
        self.add_item(item[:name], 1, item[:custom])

        if is_flag_on? "--custom_bundling"
          wait_for_enter "What else do you want to get?" 
        end

        # if item[:price] < 5.01 && is_flag_on?("--no_cheap") == false
        #   num_cheap_thing = ((5.01 - item[:price]) / cheapest_item[:price]).ceil
        #   add_item(cheapest_item[:name], num_cheap_thing)
        # end

        self.checkout

        checkout_price_string = self.find_element(:css, 'div.r-padding:nth-child(2) > div:nth-child(1) > div:nth-child(2)').text
        checkout_price = checkout_price_string.gsub(/[^0-9\.]/, '').to_f

        log "#{item[:name]}\t#{checkout_price.to_money}\t#{self.user[:first_name]} #{self.user[:last_name]}"
        sentence << "#{self.user[:first_name]} #{self.user[:last_name]}, "

        self.total_price += checkout_price

        if is_flag_on? "--sleep"
          sleep rand(1..10)
        end

        order_number += 1
      end

    end

    sentence << ". Thanks so much for helping me to pick up my delivery!"


    log "Total: #{self.total_price.to_money}"
    log "\n"
    log sentence
    log "\n"
    read_log
  end

  def checkout
    self.wait_until_visible(:xpath, "//*[@id='id_shopping_cart_checkout_form']/ul/li[3]/input")

    # checkout
    self.find_element(:xpath, "//*[@id='id_shopping_cart_checkout_form']/ul/li[3]/input").click
    self.find_element(:id, 'pickup_discount_code').send_keys '5OFF'

    self.find_element(:xpath, "//*[@id='id_pickup_form']/div[8]/div/div/div[2]/a").click

    # billing info
    if is_flag_on?("--debug")
      self.find_element(:id, 'payment_ccnumber').send_keys "1234567890"
    else
      self.find_element(:id, 'payment_ccnumber').send_keys ENV['CC_NUMBER']
    end
    
    self.find_element(:id, 'payment_nameoncard').send_keys "#{self.user[:first_name]} #{self.user[:last_name]}"

    self.find_dropdown(:id, 'payment_cctype').select_by(:text, ENV['CC_TYPE'])
    self.find_dropdown(:id, 'payment_expdatem')
      .select_by(:text, ENV['CC_EXP_MONTH'])
    self.find_dropdown(:id, 'payment_expdatey')
      .select_by(:text, ENV['CC_EXP_YEAR'])
    self.find_element(:id, 'payment_cvvcode').send_keys ENV['CC_CVV']

    if is_flag_on? "--no_confirm"
      # do not confirm
    else
      wait_for_enter 'Please confirm your order. Exit the program to cancel the order'
    end

    self.find_element(:class, 'submit-order-buttn').click
  end
end