require "rspec"
require_relative "foo"

describe "Foo" do
  it "says hello" do
    expect(Foo.hello).to eq("hello")
  end

  it "says goodbye" do
    expect(Foo.hello).to eq("goodbye")
  end
end
