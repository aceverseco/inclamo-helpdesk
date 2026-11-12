# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Ai::Calls::CardNumbers do
  def mask(text)
    described_class.mask(text)
  end

  it 'removes a card number written with spaces, with dashes and plainly' do
    expect(mask('my card is 4111 1111 1111 1111')).to eq('my card is [card number removed]')
    expect(mask('card 4111-1111-1111-1111, thanks')).to eq('card [card number removed], thanks')
    expect(mask('4111111111111111')).to eq('[card number removed]')
  end

  it 'removes card numbers of 13 and of 19 digits' do
    expect(mask('old card 4222222222222')).to eq('old card [card number removed]')
    expect(mask('long card 6304000000000000018 ok')).to eq('long card [card number removed] ok')
  end

  it 'keeps a long number that fails the Luhn check' do
    expect(mask('order 1001234567890')).to eq('order 1001234567890')
    expect(mask('4111 1111 1111 1112')).to eq('4111 1111 1111 1112')
  end

  it 'keeps short numbers, phone numbers and numbers longer than a card' do
    expect(mask('call +1 555 010 0001 about order 1042')).to eq('call +1 555 010 0001 about order 1042')
    expect(mask('tracking 41111111111111114111')).to eq('tracking 41111111111111114111')
  end

  it 'removes a card number followed by its security code, keeping the code apart' do
    expect(mask('it is 4111 1111 1111 1111 123')).to eq('it is [card number removed] 123')
  end

  it 'removes every card number of a text' do
    expect(mask('first 4111 1111 1111 1111 then 5500-0000-0000-0004.')).to eq('first [card number removed] then [card number removed].')
  end

  it 'answers what is not text as it is' do
    expect(mask(nil)).to be_nil
  end
end
