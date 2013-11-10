#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'pathname'
require 'test/unit'

require "#{Pathname(__FILE__).realpath.dirname}/moar.rb"

# Tests for the line editor
class TestLineEditor < Test::Unit::TestCase
  include Curses

  def assert_add(test_me, key, string, cursor_pos, done)
    test_me.enter_char(key)
    assert_equal(string, test_me.string, 'string')
    assert_equal(cursor_pos, test_me.cursor_position, 'cursor position')
    assert_equal(done, test_me.done?, 'done')

    if string.empty?
      assert(test_me.empty?)
    else
      assert(!test_me.empty?)
    end
  end

  def test_basic
    test_me = LineEditor.new
    assert_equal('', test_me.string)
    assert_equal(0, test_me.cursor_position)
    assert(!test_me.done?)

    assert_add(test_me, 'a'.ord, 'a', 1, false)
    assert_add(test_me, 'b'.ord, 'ab', 2, false)
    assert_add(test_me, 'c'.ord, 'abc', 3, false)

    # 127 = BACKSPACE on a Powerbook.  Key::BACKSPACE is something
    # else, don't know why they aren't one and the same.
    assert_add(test_me, 127, 'ab', 2, false)

    # 10 == RETURN on a Powerbook.  Key::ENTER is something else,
    # don't know why they aren't one and the same.
    assert_add(test_me, 10, 'ab', 2, true)
  end

  def test_out_of_range_char
    test_me = LineEditor.new
    assert_add(test_me, 42_462_124_635, '', 0, false)
  end

  # Verify that we become done after backspacing out of an empty
  # line
  def test_done_on_empty_backspace
    test_me = LineEditor.new
    assert_add(test_me, 127, '', 0, true)
  end

  def test_regexp
    # Only lower case chars => case insensitive regexp
    assert_equal(/apa/iu, LineEditor.new('apa').regexp)

    # Valid regexp => regexp
    assert_equal(/[mos]/iu, LineEditor.new('[mos]').regexp)

    # Invalid regexp => string search
    assert_equal(Encoding::UTF_8, '[mos'.encoding)
    regexp = LineEditor.new('[mos').regexp
    assert_equal(/\[mos/iu, regexp)
    assert(regexp.match('[mos'))
    assert(regexp.match('åäö [mos'))

    # One upper case char => case sensitive regexp
    assert_equal(/Apa/u, LineEditor.new('Apa').regexp)
  end

  def test_encoding
    test_me = LineEditor.new
    assert_equal(Encoding::UTF_8, test_me.string.encoding)
    assert_equal(Encoding::UTF_8, test_me.regexp.encoding)
  end

  def test_add_unicode
    test_me = LineEditor.new
    assert_add(test_me, 'ä', 'ä', 1, false)
  end
end

# A mock terminal that doesn't actually display anything
class MockTerminal
  # We can display two lines
  def lines
    return 2
  end
end

# Tests for terminal functionality
class TestTerminal < Test::Unit::TestCase
  def test_wide_getch
    # Make sure we don't break anything
    assert_equal(Curses::Key::RESIZE,
                 Terminal.new(true).wide_getch(Curses::Key::RESIZE))
    assert_equal(Curses::Key::NPAGE,
                 Terminal.new(true).wide_getch(Curses::Key::NPAGE))
    assert_equal(10, Terminal.new(true).wide_getch(10))
    assert_equal(127, Terminal.new(true).wide_getch(127))
    assert_nil(Terminal.new(true).wide_getch(nil))

    # Single byte UTF-8
    assert_equal('k', Terminal.new(true).wide_getch('k'))
    assert_equal('k', Terminal.new(true).wide_getch(107))

    # Two byte UTF-8
    assert_equal(Encoding::UTF_8,
                 Terminal.new(true).wide_getch(0xc3, 0xa4).encoding)
    assert_equal('ä', Terminal.new(true).wide_getch(0xc3, 0xa4))

    # Three byte UTF-8
    assert_equal('€', Terminal.new(true).wide_getch(226, 130, 172))

    # Four byte UTF-8
    assert_equal('😉',
                 Terminal.new(true).wide_getch(0xf0, 0x9f, 0x98, 0x89))
  end

  # Test that some bogus getch input renders a certain warning
  def assert_wide_getch_warning(expected_warning, *bytes)
    test_me = Terminal.new(true)
    assert_equal(bytes[0].chr, test_me.wide_getch(*bytes),
                 'Fallback return value should be first byte.chr')
    assert_equal(1, test_me.warnings.size)
    warning = test_me.warnings.to_a[0]
    assert(warning.include?(expected_warning),
           "Should include <#{expected_warning}>: #{warning}")
    assert(warning.start_with?('WARNING: '),
           "Should include <WARNING:>: #{warning}")
    assert(warning.include?('LANG='),
           "Should include <LANG=>: #{warning}")
  end

  def test_wide_getch_invalid_input
    assert_wide_getch_warning('start byte 255 from keyboard',
                              255)
    assert_wide_getch_warning('[0xc3, 0xff] from keyboard',
                              0xc3, 255)
    assert_wide_getch_warning('[0xe2, 0x82, 0xff] from keyboard',
                              226, 130, 255)
    assert_wide_getch_warning('[0xf0, 0x9f, 0x98, 0xff] from keyboard',
                              0xf0, 0x9f, 0x98, 0xff)
  end
end

# Tests for the pager logic
class TestMoar < Test::Unit::TestCase
  def test_line_methods
    # This method assumes the MockTerminal can display two lines
    terminal = MockTerminal.new
    test_me = Moar.new(%w(1 2 3 4), terminal)

    assert_equal(0, test_me.first_line)
    assert_equal(1, test_me.last_line)

    assert_equal(2, test_me.last_line(1))

    test_me.last_line = 2
    assert_equal(1, test_me.first_line)
    assert_equal(2, test_me.last_line)
  end

  def test_search_range
    terminal = MockTerminal.new
    test_me = Moar.new(%w(0 1 2 3 4), terminal)

    assert_equal(0, test_me.search_range(0, 4, '0'))
    assert(!test_me.search_range(1, 4, '0'))
    assert(!test_me.search_range(0, 3, '4'))
  end

  def test_search_range_with_ansi_escapes
    terminal = MockTerminal.new
    test_me = Moar.new(["#{27.chr}[mapa"], terminal)
    assert_equal(0, test_me.search_range(0, 0, 'apa'))
    assert_nil(test_me.search_range(0, 0, 'kalas'))
    assert_nil(test_me.search_range(0, 0, 'm'),
               "'m' is part of the escape code and should be ignored")
    assert_nil(test_me.search_range(0, 0, 'mapa'))
  end

  def test_full_search
    # This method assumes the MockTerminal can display two lines
    terminal = MockTerminal.new
    test_me = Moar.new(%w(0 1 2 3 4), terminal)

    assert_equal(2, test_me.full_search('2'))
    assert(!test_me.full_search('1'))
    assert_equal(2, test_me.full_search('2'))
  end

  def test_full_search_at_bottom
    # This method assumes the MockTerminal can display two lines
    terminal = MockTerminal.new
    test_me = Moar.new(%w(0 1), terminal)

    assert_equal(1, test_me.full_search('1'))
    assert_equal(1, test_me.full_search('1'))
  end
end

# Test our string-with-ANSI-control-codes class
class TestAnsiString < Test::Unit::TestCase
  ESC = 27.chr
  BS = 8.chr  # Backspace
  R = "#{ESC}[7m"  # REVERSE
  N = "#{ESC}[27m" # NORMAL
  BOLD = "#{ESC}[1m"
  NONBOLD = "#{ESC}[22m"
  UNDERLINE = "#{ESC}[4m"
  NONUNDERLINE = "#{ESC}[24m"

  def test_tokenize_empty
    count = 0
    AnsiString.new('').tokenize do |code, text|
      count += 1
      assert_equal(1, count)

      assert_equal(nil, code)
      assert_equal('', text)
    end
  end

  def test_tokenize_uncolored
    count = 0
    AnsiString.new('apa').tokenize do |code, text|
      count += 1
      assert_equal(1, count)

      assert_equal(nil, code)
      assert_equal('apa', text)
    end
  end

  def test_tokenize_color_at_start
    tokens = []
    AnsiString.new("#{ESC}[31mapa").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([%w(31m apa)], tokens)
  end

  def test_tokenize_color_middle
    tokens = []
    AnsiString.new("flaska#{ESC}[1mapa").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([[nil, 'flaska'],
                  %w(1m apa)], tokens)
  end

  def test_tokenize_color_end
    tokens = []
    AnsiString.new("flaska#{ESC}[m").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([[nil, 'flaska'], ['m', '']], tokens)
  end

  def test_tokenize_color_many
    tokens = []
    string = AnsiString.new("#{ESC}[1mapa#{ESC}[2mgris#{ESC}[3m")
    string.tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([%w(1m apa),
                  %w(2m gris),
                  ['3m', '']], tokens)
  end

  def test_tokenize_consecutive_colors
    tokens = []
    AnsiString.new("apa#{ESC}[1m#{ESC}[2mgris").tokenize do |code, text|
      tokens << [code, text]
    end

    assert_equal([[nil, 'apa'], ['1m', ''], %w(2m gris)], tokens)
  end

  def highlight(base, search_term)
    return AnsiString.new(base).highlight(search_term).to_str
  end

  def test_highlight_nothing
    assert_equal('1234', highlight('1234', '5'))

    string = "#{ESC}1mapa#{ESC}2mgris#{ESC}3m"
    assert_equal(string, highlight(string, 'aardvark'))
  end

  def test_highlight_undecorated
    assert_equal("a#{R}p#{N}a",
                 highlight('apa', 'p'))
    assert_equal("#{R}ap#{N}a",
                 highlight('apa', 'ap'))
    assert_equal("a#{R}pa#{N}",
                 highlight('apa', 'pa'))
    assert_equal("#{R}apa#{N}",
                 highlight('apa', 'apa'))

    assert_equal("#{R}a#{N}p#{R}a#{N}",
                 highlight('apa', 'a'))
  end

  def test_highlight_decorated
    string = "apa#{ESC}[31mgris#{ESC}[32morm"

    assert_equal("#{R}apa#{N}#{ESC}[31mgris#{ESC}[32morm",
                 highlight(string, 'apa'))
    assert_equal("apa#{ESC}[31m#{R}gris#{N}#{ESC}[32morm",
                 highlight(string, 'gris'))
    assert_equal("apa#{ESC}[31mgris#{ESC}[32m#{R}orm#{N}",
                 highlight(string, 'orm'))

    assert_equal("apa#{ESC}[31mg#{R}r#{N}is#{ESC}[32mo#{R}r#{N}m",
                 highlight(string, 'r'))
  end

  def test_dont_highlight_ansi_codes
    string = "3#{ESC}[3m3"

    assert_equal("#{R}3#{N}#{ESC}[3m#{R}3#{N}",
                 highlight(string, '3'))
  end

  def test_include?
    test_me = AnsiString.new("#{27.chr}[mapa")
    assert(test_me.include?('apa'))
    assert(!test_me.include?('m'),
           "'m' is part of the escape code and should be ignored")
    assert(!test_me.include?('mapa'))

    assert(AnsiString.new('räka').include?('ä'))
    assert(AnsiString.new('Ärta').include?(/ä/i))
    assert(AnsiString.new('Ärta').include?(/Ä/))
  end

  def test_plain_substring
    assert_equal('', AnsiString.new('').substring(0).to_str)
    assert_equal('', AnsiString.new('').substring(5).to_str)

    assert_equal('01234', AnsiString.new('01234').substring(0).to_str)
    assert_equal('234', AnsiString.new('01234').substring(2).to_str)
    assert_equal('', AnsiString.new('01234').substring(5).to_str)
  end

  def test_ansi_substring
    test_me =
      AnsiString.new("#{ESC}[33m012#{ESC}[34m345#{ESC}[35m678")

    assert_equal("#{ESC}[33m012#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(0).to_str)
    assert_equal("#{ESC}[33m12#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(1).to_str)
    assert_equal("#{ESC}[33m2#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(2).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m345#{ESC}[35m678",
                 test_me.substring(3).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m45#{ESC}[35m678",
                 test_me.substring(4).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m5#{ESC}[35m678",
                 test_me.substring(5).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m678",
                 test_me.substring(6).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m78",
                 test_me.substring(7).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m8",
                 test_me.substring(8).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m",
                 test_me.substring(9).to_str)
    assert_equal("#{ESC}[33m#{ESC}[34m#{ESC}[35m",
                 test_me.substring(10).to_str)
  end

  def test_manpage_bold
    assert_equal("a#{BOLD}b#{NONBOLD}c",
                 AnsiString.new("ab#{BS}bc").to_str)
    assert_equal("a#{BOLD}bc#{NONBOLD}d",
                 AnsiString.new("ab#{BS}bc#{BS}cd").to_str)
  end

  def test_manpage_underline
    assert_equal("a#{UNDERLINE}b#{NONUNDERLINE}c",
                 AnsiString.new("a_#{BS}bc").to_str)
    assert_equal("a#{UNDERLINE}bc#{NONUNDERLINE}d",
                 AnsiString.new("a_#{BS}b_#{BS}cd").to_str)
  end

  def test_manpage_bold_and_underline
    assert_equal("a#{BOLD}#{UNDERLINE}b#{NONUNDERLINE}#{NONBOLD}c",
                 AnsiString.new("a_#{BS}b#{BS}bc").to_str)
    assert_equal("a#{BOLD}#{UNDERLINE}bc#{NONUNDERLINE}#{NONBOLD}d",
                 AnsiString.new("a_#{BS}b#{BS}b_#{BS}c#{BS}cd").to_str)
  end
end
