# frozen_string_literal: true

# A Chrome window on AppealsWeb, for the scripts that need one.
#
# The site is behind Imperva, which turns away plain HTTP clients and
# headless Chrome, and now and then wants a human to pass a security check.
# So we drive a Chrome window, and when the check comes up we wait for you to
# click through it there.  Chrome keeps its profile in the directory you give
# it, so the cookie from passing the check outlives the run.

require "ferrum"

# Imperva put up its security check, or answered a request with it
class Blocked < StandardError; end

# Ferrum connects to every web worker a page starts, from the thread that
# handles all of the browser's events, and waits for the worker to answer.
# Imperva's scripts start workers that don't, which stalls that thread until
# it times out and dies, and leaves the browser deaf to us.  We have no use
# for the workers, so just let them run.
Ferrum::Contexts.prepend(Module.new do
  def connect_worker(target)
    resume(target.session_id)
  end
end)

class AppealsWeb
  URL = "https://www.sec.state.ma.us/AppealsWeb/AppealsStatus.aspx"

  # work that runs into the security check this many times gives up
  ATTEMPTS = 3

  def initialize(profile)
    @browser = Ferrum::Browser.new(headless: false, timeout: 60,
                                   browser_options: { "user-data-dir" => File.expand_path(profile) })
    @page = @browser.create_page
  end

  def quit = @browser.quit

  private

  # Run the block, and if it runs into the security check, wait for you to
  # pass it and run the block again from the start.
  def past_check
    attempt = 0
    begin
      attempt += 1
      yield
    rescue Blocked
      raise "still running into the security check after #{ATTEMPTS} tries" if attempt >= ATTEMPTS

      pass_check
      retry
    end
  end

  # Wait, as long as it takes, for you to pass the security check in the
  # Chrome window.  A request that got the check doesn't show it, so we load
  # the search page to bring it up.
  def pass_check
    @page.go_to(URL)
    return unless blocked?

    warn "\aImperva wants a security check: click through it in the Chrome window"
    sleep 1 until form_loaded?
    warn "security check passed"
  end

  def form_loaded?
    form?
  rescue Ferrum::Error
    false
  end

  def form? = @page.evaluate(%(!!document.getElementById("ddlDateType")))

  def blocked? = @page.evaluate(%(!!document.querySelector("iframe[src*='_Incapsula_Resource']")))

  def wait_for(timeout: 300)
    deadline = Time.now + timeout
    loop do
      begin
        return if yield
        raise Blocked if blocked?
      rescue Ferrum::Error
        # the page went away mid-check; try again
      end
      raise "timed out waiting for AppealsWeb" if Time.now > deadline

      sleep 0.25
    end
  end
end
