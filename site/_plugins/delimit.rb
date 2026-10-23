# Liquid has no thousands separator, so `{{ 6883 | delimit }}` -> "6,883".
module Delimit
  # Only groups a run of digits that reaches the end of the string, so a sign
  # ("-1234") comes through and anything that isn't a plain integer ("12.5",
  # "6883 PDFs") is left alone rather than grouped in the wrong places.
  def delimit(number)
    number.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')
  end
end

Liquid::Template.register_filter(Delimit)
