require_relative '../lib/sites/base_clinic'

class MockStorage
  def initialize(last_posted_time)
    @last_posted_time = last_posted_time
  end

  def get_post_time(_)
    @last_posted_time
  end
end

class MockClinic < BaseClinic
  attr_reader :title, :appointments, :new_appointments, :link, :city

  def initialize(title: 'Mock clinic on 01/01/2021',
                 appointments: 0,
                 new_appointments: 0,
                 link: 'clinicsite.com',
                 last_posted_time: nil,
                 city: nil)
    super(MockStorage.new(last_posted_time))
    @title = title
    @appointments = appointments
    @new_appointments = new_appointments
    @link = link
    @last_posted_time = last_posted_time
    @city = city
  end

  def storage_key
    title
  end

  def save_tweet_time
    nil
  end
end
