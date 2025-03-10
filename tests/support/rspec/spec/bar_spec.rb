require "rspec"
require_relative "bar"

describe "Bar" do
  it "says hello" do
    expect(Bar.hello).to eq("hello")
  end

  it "says goodbye" do
    expect(Bar.hello).to eq("goodbye")
  end
end
