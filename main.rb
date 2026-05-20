require 'set'
require 'fileutils'

class CorruptSaveError < StandardError; end

#Useful functions for the interaction with the user
module Answers
  #print popup message
  def popup(msg = nil, duration = 1.5)
    puts msg if msg
    sleep(duration)
    print "\e[1A\e[2K"
  end

  #true if yes, false if no
  def yes_no_question(question)
    puts question
    option = gets.chomp
    until ['yes', 'y', 'no', 'n'].include? option.downcase
      popup "Invalid input"
      print "\e[1A\e[2K"

      option = gets.chomp
    end

    if ['yes', 'y'].include? option.downcase
      2.times { print "\e[1A\e[2K" }
      true
    else
      2.times { print "\e[1A\e[2K" }
      false
    end
  end

  #return the choosen answer (all answers must be strings)
  def mult_ans_question(question, answers)
    puts question
    answers.each_with_index {|ans, idx| puts (idx + 1).to_s + ". " + ans}

    valid_inputs = answers.map(&:downcase) + (1..answers.size).map(&:to_s)

    option = gets.chomp
    until valid_inputs.include? option.downcase
      popup "Invalid input"
      print "\e[1A\e[2K"
      option = gets.chomp
    end

    (2 + answers.size).times { print "\e[1A\e[2K" }

    option = answers[option.to_i - 1] unless answers.include?(option)
    option
  end
end

#Handles loading/saving data and comunication with the user regarding this topic
module DataManagement
  include Answers

  private

  #provides the path to the save folder
  #and it creates that folder if it does not yet exist
  def get_path(id)
    path = "saves/save#{id}"
    FileUtils.mkdir_p("saves") unless Dir.exist?("saves")
    FileUtils.mkdir_p(path)    unless Dir.exist?(path)
    path
  end

  def folder_empty?(path); Dir.empty?(path) end

  #true if a savefile of such id exists
  def good_id(id)
    return true if (0..3).include?(id) 
    popup "Savefile 'save#{id}' does not exist."
    false
  end

  #saves board data, the history of the moves performed during the session, 
  #and the number of turns performed
  def save(id)
    path = get_path(id)

    File.open("#{path}/board", "w") do |file|
      (1..8).each do |x|
        (1..8).each do |y|
          piece = Chess.board.get_field(x, y).piece
          klass = piece.class
          if piece
            color = piece.color
            has_moved = piece.has_moved
          end
          file.puts "#{klass} #{color} #{has_moved}"
        end
      end
    end

    File.open("#{path}/history", "w") do |file|
      @history.each do |white_move, black_move|
        file.puts [ white_move, black_move ].compact.join("\t")
      end
    end

    File.open("#{path}/turn", "w") do |file|
      file.puts @turn_count
    end

    popup "Game saved sussessfully." unless id == 0
    true
  end

  #loads the saved data (returns an error if the data does not exist of is corrupted)
  def load(id)
    path = get_path(id)

    if folder_empty?(get_path(id))
      popup "The choosen save is empty."
      return false
    end

    Chess.players = {:white => Player.new(:white), :black => Player.new(:black)}
    Chess.board = Board.new

    begin
      File.open("#{path}/board", "r") do |file|
        (1..8).each do |x|
          (1..8).each do |y|
            data = file.readline.strip
            if data == "NilClass"
              #puts "#{x} #{y}:\t #{data}"
              Chess.board.get_field(x, y).piece = nil
            else
              klass_str, color_str, has_moved_str = data.match(/^(\w+)\s+(\w+)\s+(\w+)$/).captures
              #puts "#{x} #{y}:\t#{klass_str} #{color_str} #{has_moved_str}"
              klass =
                begin
                  Object.const_get(klass_str)
                rescue NameError
                  raise CorruptSaveError, "Unknown class #{klass_str}"
                end
              
              color = color_str.to_sym
              has_moved = 
              case has_moved_str
              when 'true' then true
              when 'false' then false
              else raise CorruptSaveError, "Invalid moved flag '#{has_moved_str}'"
              end

              field = Chess.board.get_field(x, y)
              field.init_piece(klass, color)
              field.piece.has_moved = has_moved

              # Assign the king if this is a King piece
              if field.piece.is_a?(King)
                unless Chess.players[color].king
                  raise CorruptSaveError, "There are multiple kings of the same type on the board"
                end
                Chess.players[color].king = field.piece 
              end
            end
          end
        end
      end

      @history = []

      File.open("#{path}/history", "r") do |file|
        file.each_line do |line|
          white, black = line.chomp.split("\t")
          @history << [ white, black ]
        end
      end

      File.open("#{path}/turn", "r") do |file|
        @turn_count = file.readline.strip.to_i
      end

      # Ensure check status is updated
      if Chess.players[:white].king.checkmated || Chess.players[:black].king.checkmated
        puts "The game saved on this save has already ended."
        return false
      end

      unless id == 0; puts "save#{id} loaded."
      else; puts "recovered last game."
      end
      popup

      return true

    rescue EOFError
      puts "Save file truncated!"
      :error
    rescue CorruptSaveError => e
      puts "Corrupted save data: #{e.message}"
      :error
    end
  end

  public

  #while stopping program with Ctrl+C, closes elegantly
  #reminds the user about saving the progress
  def setup_signal_trap
    return if defined?(@@trap_initialized) && @@trap_initialized
    @@trap_initialized = true
    @@close = false

    Signal.trap("INT") do
      if @game_state.nil? && @turn_count > 1
        until @@close do
          if yes_no_question("You are trying to close the game. Do you wish to save the progress?")
            id = mult_ans_question("Choose the save you want to save the game at: ", ["1", "2", "3"])
            if save(id)
              delete_save(0)
              popup("Game will close momentarily.", 1)
              popup("Game closed.", 1)

              @@close = true
              system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
              exit
            end
          else
            if yes_no_question("Are you sure?")
              delete_save(0) unless folder_empty?(get_path(0))
              popup("Game will close momentarily.", 1)
              popup("Game closed.", 1)

              @@close = true
              system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
              exit
            end
          end
        end
      else
        unless @@close
          popup("Game will close momentarily.", 1)
          popup("Game closed.", 1)
          @@close = true
          system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
          exit
        end
      end
    end
  end

  #saves the data in case of an unexpected exit
  def auto_save; self.save(0) end

  #informs the used of an unsaved game
  #gives an oppotrunity to load of save the game
  def auto_save_rescue
    get_path(0)
    unless Dir.children("saves/save0").empty?
      loop do
        case mult_ans_question("Unsaved game data found. Would you like to resume or save the game?", ["continue", "save", "no"])
        when "continue" then
          if load(0)
            return true
          else
            delete_save(0); 
            return false
          end
        when "save" then 
          if load(0)
            id = mult_ans_question("Choose the save you want to save the game at: ", ["1", "2", "3"])
            if save(id)
              delete_save(0)
              return true
            end
          else
            return false
          end
        when "no" then
          if yes_no_question("The game data will be lost. Are you sure you want to erase the data?")
            delete_save(0)
            return true
          end
        end
      end
    end
  end

  #deletes the save file's content
  def delete_save(id)
    return unless id == 0 || good_id(id)

    path = get_path(id)

    if folder_empty?(path)
      popup "This save is already empty." if id != 0
      return
    end

    Dir.foreach(path) do |file|
      next if file == '.' || file == '..'
      file_path = File.join(path, file)
      File.directory?(file_path) ? FileUtils.rm_rf(file_path) : File.delete(file_path)
    end
  end

  #responds to the 'save' command during the play
  def save_to
    return if @turn_count == 1

    id = mult_ans_question("Choose the save you wish save the game on: ", ('1'..'3').to_a)
    unless folder_empty?(get_path(id))
      save(id) if yes_no_question("The selected save is already being used. Do you wish to overwrite it?")
    end
  end

  #handles the 'save' option in the main menu
  #there are options to save or delete the save file
  def saves_options
    done = false
    until done
      id = mult_ans_question("Choose the save: ", ['1', '2', '3', 'back'])
      unless id == 'back'
        case mult_ans_question("What do you want to do with that save?", ["load", "delete"])
        when "load"   then @save_loaded = true if load(id)
        when "delete" then delete_save(id.to_i) if yes_no_question("Are you sure?")
        end
      else 
        done = true
      end 
    end
    true
  end
end

#Movement management for the chess figures which use patterns to move
module JumpMovement
  #handles the asymmetric patterns
  def self.asymm_pattern(klass, beg, color, has_moved = true, symmetry = :asymmetric, x_sig = 1, y_sig = 1)
    move_storage = []
    reflection = klass.is_pattern_reflective && color == :black ? -1 : 1
    patterns = (has_moved ? klass.move_pattern : klass.first_moves)

    [:general, :passive, :attacking].each do |mode|
      patterns[symmetry][mode].each do |x_add, y_add|
        x = beg[0] + x_add * x_sig * reflection
        y = beg[1] + y_add * y_sig * reflection
        next unless (1..8).include?(x) && (1..8).include?(y)

        field = Chess.board.get_field(x, y)
        case mode
        when :general
          if field.piece.nil?
            move_storage << [x, y, :passive]
          elsif field.piece.color != color 
            move_storage << [x, y, :attacking]
          end
        when :passive
          move_storage << [x, y, :passive] if field.piece.nil?
        when :attacking
          move_storage << [x, y, :attacking] if field.piece && field.piece.color != color
        end
      end
    end
    move_storage
  end

  #handles the symmetric patterns
  def self.symm_pattern(klass, beg, color, has_moved = true)
    move_storage = []
    [[-1, -1], [-1, 1], [1, -1], [1, 1]].each do |x_sig, y_sig|
      move_storage += asymm_pattern(klass, beg, color, has_moved, :symmetric, x_sig, y_sig)
    end
    move_storage
  end

  #see Piece#is_on_pattern (move, color, consider_mode = true)
  def self.is_on_pattern(klass, move, color, consider_mode)
    move_storage = asymm_pattern(klass, move.beginning, color) +
                   symm_pattern(klass, move.beginning, color) +
                   asymm_pattern(klass, move.beginning, color, false) +
                   symm_pattern(klass, move.beginning, color, false)

    if consider_mode
      mode = move.attacking ? :attacking : :passive
      move_storage.include?([move.end_x, move.end_y, mode])
    else
      move_storage.each do |x, y, _|
        return true if move.end_x == x && move.end_y == y
      end
      return false
    end
  end

  #see Piece#get_possible_moves
  def get_possible_moves
    @poss_moves = JumpMovement.asymm_pattern(self.class, @pos, @color) +
                  JumpMovement.symm_pattern(self.class, @pos, @color)
    unless @has_moved
      @poss_moves += JumpMovement.asymm_pattern(self.class, @pos, @color, false) +
                     JumpMovement.symm_pattern(self.class, @pos, @color, false)
    end
  end
  
  #in-between function for the self.is_on_pattern
  def is_on_pattern(move, consider_mode = true)
    JumpMovement.is_on_pattern(self.class, move, @color, consider_mode)
  end

  #see Piece#get_check_block_fields
  def get_check_block_fields; return [@pos[0], @pos[1], :attacking] end
end

#Movement management module from which other VerticalMovement, HorizontalMovement and DiagonalMovement 'inherit'
module LinearMovement
  #see Piece#get_possible_moves
  def get_possible_moves(signs)

    signs.each do | x_sig, y_sig |
      x = @pos[0] + 1 * x_sig
      y = @pos[1] + 1 * y_sig
      # passive moves
      while (1..8).include?(x) && (1..8).include?(y) &&
            Chess.board.get_field(x, y).piece == nil
        @poss_moves << [x, y, :passive]
        x += 1 * x_sig
        y += 1 * y_sig
      end

      # attacking move
      if (1..8).include?(x) && (1..8).include?(y) && 
          Chess.board.get_field(x, y).piece &&
          Chess.board.get_field(x, y).piece.color != @color
        @poss_moves << [x, y, :attacking]
      end
    end
  end

  #see Piece#get_check_block_fields
  def get_check_block_fields
    block_moves = []
    beg_pos = @pos.dup
    end_pos = Chess.players[@color != :white ? :white : :black].king.pos
    x_add = end_pos[0] <=> beg_pos[0]
    y_add = end_pos[1] <=> beg_pos[1]

    while beg_pos != end_pos
      field_piece = Chess.board.get_field(beg_pos[0], beg_pos[1]).piece
      block_moves << [beg_pos[0], beg_pos[1], (field_piece ? :attacking : :passive)]
      beg_pos[0] += x_add
      beg_pos[1] += y_add
    end
    block_moves
  end
end

#Piece vetrical movement management
module VerticalMovement
  include LinearMovement

  #see Piece#get_possible_moves
  def get_possible_moves
    LinearMovement.instance_method(:get_possible_moves).bind(self).call([[-1, 0], [1, 0]])
  end

  #see Piece#is_on_pattern (move, color, consider_mode = true)
  def self.is_on_pattern(move)
    return move.beg_x == move.end_x
  end
end

#Piece horizontal movement management
module HorizontalMovement
  include LinearMovement

  #see Piece#get_possible_moves
  def get_possible_moves
    LinearMovement.instance_method(:get_possible_moves).bind(self).call([[0, -1], [0, 1]])
  end

  #see Piece#is_on_pattern (move, color, consider_mode = true)
  def self.is_on_pattern(move)
    return move.beg_y == move.end_y
  end
end

#Piece diagonal movement management
module DiagonalMovement
  include LinearMovement

  #see Piece#get_possible_moves
  def get_possible_moves
    LinearMovement.instance_method(:get_possible_moves).bind(self).call([[-1, -1], [-1, 1], [1, -1], [1, 1]])
  end

  #see Piece#is_on_pattern (move, color, consider_mode = true)
  def self.is_on_pattern(move)
    return  move.beg_x - move.beg_y == move.end_x - move.end_y ||
            move.beg_x + move.beg_y == move.end_x + move.end_y
  end
end

#Holds the information about the chess field and handles its updates
class Field
  attr_accessor :pos, :color, :piece

  def initialize(pos, color)
    @pos = pos
    @color = color
  end

  def to_s
    if @piece
      bg = @color == :black ? 40 : 47
      fg = @piece.color == :black ? 34 : 33   #30 : 37

      "\e[#{bg}m\e[#{fg}m#{@piece.to_s}\e[0m"
    else
      bg = @color == :black ? 40 : 47
      "\e[#{bg}m \e[0m"
    end
  end

  #sets a new piece on the board
  def init_piece(piece, color)
    @piece = piece.new(color, @pos)
  end

  #updates the piece on the board
  #directs information about the eliminations to the player
  #and updates the new piece's position
  def update(new_piece)
    if @piece && new_piece
      Chess.players[@piece.color].delete_piece(@piece)
    end

    @piece = new_piece

    @piece.pos = @pos if @piece
  end
end

#A container class for the Field objects
#handles the state of the chess board and its states
class Board
  attr_accessor :board, :history

  def initialize
    @board = Array.new(9) do |i|
      Array.new(9) do |j|
        Field.new([i, j], (i % 2 == j % 2 ? :black : :white))
      end
    end
    @history = []
  end

  def to_s
    output = ""
    (1..8).reverse_each do | x |
      output += x.to_s + " "
      (1..8).each do | y |
        output += board[y][x].to_s
        bg = (x % 2 == y % 2) ? 40 : 47
        output += "\e[#{bg}m \e[0m"
      end
      bg = x % 2 ? 40 : 47
      output += "\e[#{bg}m\e[0m\n"
    end
    output += "  a b c d e f g h"
    output
  end

  #sets the board for the new game of chess
  def set
    @board[1][1].init_piece(Rook,   :white)
    @board[8][1].init_piece(Rook,   :white)
    @board[2][1].init_piece(Knight, :white)
    @board[7][1].init_piece(Knight, :white)
    @board[3][1].init_piece(Bishop, :white)
    @board[6][1].init_piece(Bishop, :white)
    @board[4][1].init_piece(Queen,  :white)
    @board[5][1].init_piece(King,   :white)

    (1..8).each do | i |
      board[i][2].init_piece(Pawn,  :white)
      board[i][7].init_piece(Pawn,  :black)
    end

    @board[1][8].init_piece(Rook,   :black)
    @board[8][8].init_piece(Rook,   :black)
    @board[2][8].init_piece(Knight, :black)
    @board[7][8].init_piece(Knight, :black)
    @board[3][8].init_piece(Bishop, :black)
    @board[6][8].init_piece(Bishop, :black)
    @board[4][8].init_piece(Queen,  :black)
    @board[5][8].init_piece(King,   :black)
  end

  #returns the field
  def get_field(x, y)
    @board[x][y]
  end

  #updates the fields involved in the move
  #records the state of those fields and the pieces on them
  #in case of the reversion of the move
  def update(piece, move)
    @history << []
    record_snapshot(piece.pos)
    record_snapshot([move.end_x, move.end_y])

    from = board[piece.pos[0]][piece.pos[1]]
    to   = board[move.end_x][move.end_y]

    from.update(nil)

    #en passant
    if move.en_passant
      y_add = (piece.color == :white ? -1 : 1)
      elim_field = board[move.end_x][move.end_y + y_add]
      record_snapshot(elim_field.pos)
      elim_field.update(nil)
    end

    #normal move
    unless move.promoting_to
      to.update(piece)
      piece.pos = [move.end_x, move.end_y]
      piece.has_moved = true
    
    #piece promotion
    else
      Chess.players[piece.color].delete_piece(piece)
      new_piece = move.promoting_to.new(piece.color, [move.end_x, move.end_y])
      to.update(new_piece)
    end
  end

  #reverse the last changes that happened on the board
  def revert_changes
    entry = @history.pop or return

    entry.each do |field_pos, before_piece, hasnt_move|
      x, y = field_pos
      after = board[x][y]

      if before_piece && after.piece
        Chess.players[before_piece.color].pieces[before_piece.class] << before_piece
      end

      if hasnt_move
        before_piece.has_moved = false
      end

      after.piece = before_piece
      after.piece.pos = [x, y] if after.piece
    end
  end

  #if the last performed move gives an opportunity for an en passant
  #return the coordinates of the field that needs to be attacked for the en passant capture
  def en_passant_target_field
    snapshot = history.last
    if snapshot.size == 2
      occupied = snapshot[0]
      empty = snapshot[1]
      occupied, empty = empty, occupied if empty[1]
      y_add = (occupied[1].color == :white ? 1 : -1)
      if occupied[2] && occupied[1].class == Pawn && (empty[0][1] - occupied[0][1]).abs == 2
        return [occupied[0][0], occupied[0][1] + y_add]
      end
    end
  end

  private
  #record the field on the given possition, the piece on it and whether the piece has moved
  def record_snapshot(pos)
    x, y = pos
    field = @board[x][y]
    @history.last << [ [x,y], field.piece, field.piece && !field.piece.has_moved ]
  end
end

#A container class for the parsed movement command
#the movement is parsed based on the algebraic chess notation
class Move
  attr_accessor :piece, :beginning, :ending, :attacking
  attr_accessor :checking, :checkmating, :promoting_to
  attr_accessor :en_passant
  #(the parser does not take into the account the 'e.p.' notation for the en passant; en passant is treated like any other attacking move)

  def initialize(piece = nil, beginning = nil, ending = nil, attacking = false, checking = false, checkmating = false, promoting_to = nil)
    @piece = piece
    @beginning = beginning
    @ending = ending
    @attacking = attacking
    @checking = checking
    @checkmating = checkmating
    @promoting_to = promoting_to
  end
  
  def to_s
    str = []
    if @piece != Pawn
      str += [Piece.find_class_symbol(piece)]
    end

    if @beginning != nil
      if @beginning[0] 
        str += [(@beginning[0] + 96).chr]
      end
      
      str += [@beginning[1].to_s]
    end

    if @attacking; str += ["x"]; end

    if @ending[0] == 0
      str = ["0-0-0"]
    elsif @ending[1] == 0
      str = ["0-0"]
    else
      str += [(@ending[0] + 96).chr]
      str += [@ending[1].to_s]
    end

    if @promoting_to; str += ["="] + [Piece.find_class_symbol(@promoting_to)]; end
    if @checking && !@checkmating; str += ["+"]; end
    if @checkmating; str += ["#"]; end

    str.join
  end

  #parse the move command
  def parse_move(str)
    if str.length <= 1; return; end

    # Parsing for castling
    case str
    when "O-O",    "0-0"     then @piece = Rook; @ending = [1, 0];                                        return self
    when "O-O+",   "0-0+"    then @piece = Rook; @ending = [1, 0]; @checking = true;                      return self
    when "O-O#",   "0-0#"    then @piece = Rook; @ending = [1, 0]; @checking = true; @checkmating = true; return self
    when "O-O-O",  "0-0-0"   then @piece = Rook; @ending = [0, 1];                                        return self
    when "O-O-O+", "0-0-0+"  then @piece = Rook; @ending = [0, 1]; @checking = true;                      return self
    when "O-O-O#", "0-0-0#"  then @piece = Rook; @ending = [0, 1]; @checking = true; @checkmating = true; return self
    end

    chars = str.chars

    rows = ('1'..'8')
    cols = ('a'..'h')
    promotion_symbols = ["=", "/"]
    endings = ["+", "#"]

    # Checking whether move should cause check or checkmate
    # And whether or not it should cause a promotion of the piece
    parse_ending = ->(chars) do
      if chars[-1] && chars[-1] == "+"
        @checking = true
        chars.pop
      
      elsif chars[-1] && chars[-1] == "#"
        @checking = true
        @checkmating = true
        chars.pop
      end
      
      if chars[-1] && Piece.parse_symbols.include?(chars[-1])
        @promoting_to = Piece.find_class(chars[-1])
        chars.pop
        if chars[-1] && promotion_symbols.include?(chars[-1]); chars.pop; end
      end
    end

    # Pawn move
    if cols.include?(chars[0])
      @piece = Pawn
      parse_ending.call(chars)

      if chars[1] && rows.include?(chars[1]) 
        # example e4
        @ending = [chars[0].ord - 'a'.ord + 1, chars[1].to_i]
        return chars[2] ? nil : self
      
      elsif chars[1] == 'x'
        # move should attack another piece
        @beginning = [chars[0].ord - 'a'.ord + 1, nil]
        @attacking = true

        if chars[2] && cols.include?(chars[2])
          if chars[3] == nil
            # example exd
            @ending = [chars[2].ord - 'a'.ord + 1, nil]
            return self
          elsif chars[3] && rows.include?(chars[3]) 
            # example exd4
            @ending = [chars[2].ord - 'a'.ord + 1, chars[3].to_i]
            return chars[4] ? nil : self
          
          else; return nil; end
        else; return nil; end
      else; return nil; end
    
    # Other pieces
    elsif Piece.parse_symbols.include?(chars[0])
      @piece = Piece.find_class(chars[0])
      parse_ending.call(chars)
      chars = chars.drop(1)

      # Parsing the beginning field (disambiguation)
      if  chars[0] && cols.include?(chars[0]) &&
          chars[1] && (chars[1] == 'x' || cols.include?(chars[1]))
        # example Rh...
        @beginning = [chars[0].ord - 'a'.ord + 1, nil]
        chars = chars.drop(1)
      elsif chars[0] && rows.include?(chars[0]) &&
            chars[1] && (chars[1] == 'x' || cols.include?(chars[1]))
        # example R4...
        @beginning = [nil, chars[0].to_i]
        chars = chars.drop(1)
      elsif chars[0] && cols.include?(chars[0]) &&
            chars[1] && rows.include?(chars[1]) && 
            chars[2] && (chars[2] == 'x' || cols.include?(chars[2]))
        # example Rh4...
        @beginning = [chars[0].ord - 'a'.ord + 1, chars[1].to_i]
        chars = chars.drop(2)
      end
      
      # Attacking move
      if chars[0] && chars[0] == 'x'
        @attacking = true
        chars = chars.drop(1)
      end

      # Ending field
      if  chars[0] && cols.include?(chars[0]) &&
          chars[1] && rows.include?(chars[1])
        @ending = [chars[0].ord - 'a'.ord + 1, chars[1].to_i]
        chars = chars.drop(2)
      else; return nil
      end

      return chars.empty? ? self : nil
      
    else; return nil; end 
  end

  #getters for the choosen beginning/ending coordinates
  def beg_x; @beginning ? @beginning[0] : nil; end
  def beg_y; @beginning ? @beginning[1] : nil; end
  def end_x;    @ending[0];    end
  def end_y;    @ending[1];    end

end

#An abstract class from which all chess pieces inherit
class Piece

  #provides a unique id needed for hashing
  def self.next_id
    Piece.instance_variable_set(:@id_counter, 0) unless Piece.instance_variable_defined?(:@id_counter)
    Piece.instance_variable_set(:@id_counter, Piece.instance_variable_get(:@id_counter) + 1)
  end

  #subclass variables that need to be inferited by all the subclasses

  #@promotable_to
  #Pawns, as they reach the other end of the board need to undergo a promotion
  #A move that changes the piece's type (or in our case removes a pawn and creates such piece in its place).
  #@promotable to holds the classes of the pieces the piece of the current type can get promoted to.

  #@move_pattern
  #Some pieces have a specific movement patterns 
  #eg. Knight goes two fields in one direction and then one field perpendicularly.
  #Most of thoose moves can be described as 'jumps'.
  #Knight's moves are symmetrical with respect to its position, so they are categorised as symmetrical,
  #while pawns can move and attack in only one direction - assymetrically.
  #Knight can also attack with each of its moves, which makes those moves general.
  #In contrast, pawns moves for attacking and moving onto an empty space are different - they have passive and attacking moves.

  #@first_moves
  #Some pieces like pawns have moves that can be performed only once. Those patterns are stored in the @first_moves hash.

  #@is_pattern_reflective
  #Pawns of different colors move the same way, but in the opposite directions,
  #so black pawns' assimetrical patterns patterns need to be reflected.
  def self.inherited(subclass)
    subclass.instance_variable_set(:@is_initialized, false)
    subclass.instance_variable_set(:@promotable_to, [])
    subclass.instance_variable_set(:@move_pattern, {
      asymmetric: { general: [], passive: [], attacking: [] },
      symmetric:  { general: [], passive: [], attacking: [] }
    })
    subclass.instance_variable_set(:@first_moves, {
      asymmetric: { general: [], passive: [], attacking: [] },
      symmetric:  { general: [], passive: [], attacking: [] }
    })
    subclass.instance_variable_set(:@is_pattern_reflective, false)
  end

  attr_accessor :color, :pos, :poss_moves, :has_moved

  protected
  def self.class_init; self.class; end

  private
  def self.is_initialized; @is_initialized; end
  def self.is_initialized=(val); @is_initialized = val; end

  def hash; @id.hash end

  public

  def initialize(color, pos)
    @id = Piece.next_id
    @color = color
    @pos = pos
    @poss_moves = []
    @has_moved = false

    unless self.class.is_initialized
      self.class.class_init
      self.class.is_initialized = true
    end

    Chess.players[color].pieces[self.class] << self
  end

  def eql?(other)
    other.is_a?(Piece) && self.class == other.class && @id == other.id
  end

  def to_s
    Piece.piece_strings[self.color][self.class] || "?"
  end

  #directs a command to update the board in accordance to the move
  def make_move(move)
    Chess.board.update(self, move)
  end

  #returns true if the move is in the pool of possible moves for the piece
  #consider mode decides whether or not the detection should take the mode of the move into the account during
  #determining the result (if the end possition is on the passive pattern, but the move is attacking)
  def has_possible_move(move, consider_mode = true)
    unless @poss_moves_generated
      self.get_possible_moves
      @poss_moves_generated = true
    end

    if consider_mode
      mode = move.attacking ? :attacking : :passive
      search_obj = [move.end_x, move.end_y, mode]

      return @poss_moves.index(search_obj) ? true : false
    else
      @poss_moves.each do |x, y, _|
        return true if move.end_x == x && move.end_y == y
      end
      return false
    end
  end

  #true, if the end position of the move matches with the movement pattern
  #requires a move to have disambiguated beginning possition
  #consider mode decides whether or not the detection should take the mode of the move into the account during
  #determining the result (if the end possition is on the passive pattern, but the move is attacking)
  def self.is_on_pattern(move, color, consider_mode = true); end

  #generates all possible end possitions for the piece's next move
  #the possitions are stored as a tuple [x coordinate, y coordinate, move's mode which allows for this position]
  def get_possible_moves; end
  #returns all fields that can block the check given by the piece, if the opponints piece captures that field
  def get_check_block_fields; end

  #reset the possible moves pool (since it could've changed since the begining of the turn)
  def turn_reset
    @poss_moves = []
    @poss_moves_generated = false
  end

  def self.promotable;    @promotable_to.any? end
  def self.promotable_to; @promotable_to; end

  def self.move_pattern;  @move_pattern; end
  def self.first_moves;   @first_moves; end

  def self.is_pattern_reflective;       @is_pattern_reflective; end
  def self.is_pattern_reflective=(val); @is_pattern_reflective = val; end
end

#Represents a pawn chess piece
class Pawn < Piece
  include JumpMovement

  private

  def self.class_init
    move_pattern[:asymmetric][:passive].concat([[0, 1]])
    move_pattern[:asymmetric][:attacking].concat([[-1, 1], [1, 1]])
    first_moves[:asymmetric][:passive].concat([[0, 2]])
    @promotable_to = [Rook, Knight, Bishop, Queen]

    self.is_pattern_reflective = true
  end

  public

  def initialize(color, pos)
    super(color, pos)
  end

  #en passant does not appear in the movement pattern nor it is included in the possible positions
  #en passant is handled by the Player#make_move method directly
  def self.is_on_pattern(move, color, consider_mode = true)
    JumpMovement.is_on_pattern(self, move, color, consider_mode)
  end

  def get_possible_moves
    JumpMovement.instance_method(:get_possible_moves).bind(self).call

    #don't allow the two-forward movement if the field in between is obstructed
    unless @has_moved
      y_add = (@color == :white ? 1 : -1)
      if Chess.board.get_field(@pos[0], @pos[1] + y_add).piece
        @poss_moves.delete([@pos[0], @pos[1] + 2*y_add, :passive])
      end
    end
  end
end

#Represents a rook chess piece
class Rook < Piece
  include VerticalMovement, HorizontalMovement

  private

  def self.class_init; end

  public

  def initialize(color, pos)
    super(color, pos)
  end

  def make_move(move)
    unless [[0, 1], [1, 0]].include?(move.ending)
      super(move)
    else
      king = Chess.players[color].king

      sng = (move.ending == [1, 0] ? -1 : 1)
      king.make_move(Move.new(King, king.pos, [@pos[0] + sng, @pos[1]]))
      super(Move.new(Rook, @pos, [@pos[0] + 2 * sng, @pos[1]]))
    end
  end

  def self.is_on_pattern(move, color, _)
    unless [[0, 1], [1, 0]].include?(move.ending)
      return VerticalMovement.is_on_pattern(move) || HorizontalMovement.is_on_pattern(move)
    
    #check if the castling is possible
    else
      player = Chess.players[color]
      unless player.king.has_moved
        player.pieces[Rook].each do |rook|
          if !rook.has_moved && rook.pos[1] == player.king.pos[1]
            return true if move.ending == [0, 1] && rook.pos[0] == 1  #queenside castling
            return true if move.ending == [1, 0] && rook.pos[0] == 8  #kingside  castling
          end
        end
      end
    end

    return false
  end

  def get_possible_moves
    VerticalMovement.instance_method(:get_possible_moves).bind(self).call
    HorizontalMovement.instance_method(:get_possible_moves).bind(self).call

    #check if the castling is possible
    king = Chess.players[color].king
    unless @has_moved || king.has_moved
      unless @poss_moves.index([king.pos[0] + 1, king.pos[1], :passive]).nil?
        @poss_moves << [1, 0, :passive]
      end
      unless @poss_moves.index([king.pos[0] - 1, king.pos[1], :passive]).nil?
        @poss_moves << [0, 1, :passive]
      end
    end
  end
end

#Represents a knight chess piece
class Knight < Piece
  include JumpMovement

  private

  def self.class_init
    move_pattern[:symmetric][:general].concat([[1, 2], [2, 1]])
  end

  public

  def initialize(color, pos)
    super(color, pos)
  end

  def self.is_on_pattern(move, color, consider_mode = true)
    JumpMovement.is_on_pattern(self, move, color, consider_mode)
  end

  def get_possible_moves
    JumpMovement.instance_method(:get_possible_moves).bind(self).call
  end
end

#Represents a bishop chess piece
class Bishop < Piece
  include DiagonalMovement

  private

  def self.class_init
    move_pattern[:symmetric][:general].concat([[1, 2], [2, 1]])
  end

  public

  def initialize(color, pos)
    super(color, pos)
  end

  def self.is_on_pattern(move, color, _)
    DiagonalMovement.is_on_pattern(move)
  end

  def get_possible_moves
    DiagonalMovement.instance_method(:get_possible_moves).bind(self).call
  end
end

#Represents a queen chess piece
class Queen < Piece
  include VerticalMovement, HorizontalMovement, DiagonalMovement

  private

  def self.class_init
    move_pattern[:symmetric][:general].concat([[1, 2], [2, 1]])
  end

  public

  def initialize(color, pos)
    super(color, pos)
  end

  def self.is_on_pattern(move, color, _)
    VerticalMovement.is_on_pattern(move) ||
    HorizontalMovement.is_on_pattern(move) ||
    DiagonalMovement.is_on_pattern(move)
  end

  def get_possible_moves
    VerticalMovement.instance_method(:get_possible_moves).bind(self).call
    HorizontalMovement.instance_method(:get_possible_moves).bind(self).call
    DiagonalMovement.instance_method(:get_possible_moves).bind(self).call
  end
end

#Represents a king chess piece
class King < Piece
  include JumpMovement

  attr_accessor :checked_by

  private

  def self.class_init
    move_pattern[:symmetric][:general].concat([[1, 0], [0, 1], [1, 1]])
  end

  public

  def initialize(color, pos)
    super(color, pos)
    Chess.players[color].king = self
    @checked_by = []
  end

  def self.is_on_pattern(move, color, consider_mode = true)
    JumpMovement.is_on_pattern(self, move, color, consider_mode)
  end

  def get_possible_moves
    JumpMovement.instance_method(:get_possible_moves).bind(self).call
  end

  #true if the king is currently in check
  #by checking if the field it stands on is being attacked by any of the opponent's pieces
  def in_check
    enemy_color = (color == :white ? :black : :white)
    is_checked = false

    Chess.players[enemy_color].pieces.values.flatten.each do |piece|
      piece.get_possible_moves
      if piece.poss_moves.include?([@pos[0], pos[1], :attacking])
        is_checked = true
        @checked_by << piece unless @checked_by.find_index(piece)
      end
      piece.turn_reset
    end

    is_checked
  end

  private

  #returns all the positions that after being captured by the ally piece (or the king itself)
  #result in the end of the check
  def check_block_poss
    block_poss = checked_by[0].get_check_block_fields

    checked_by.drop(1).each do |piece|
      block_poss &= piece.get_check_block_fields
    end

    block_poss
  end

  #goes through all of the allied pieces and checks whether of not they possess a mov that could end the check.
  #Also checks whether the king can escape the check by moving.
  #The moves are saved in the player's solve_check hash - the moves for the king and for the other pieces separately.
  #The moves are saved as the tuples [x coordinate, y coordinate, move's mode which allows for this position]
  def checkmate_defense
    player = Chess.players[@color]
    self.get_possible_moves

    block_poss = self.check_block_poss

    player.pieces.values.flatten.each do |piece|
      piece.get_possible_moves
      next if piece.is_a?(King)

      common = piece.poss_moves & block_poss
      player.solve_check[:other] |= common
    end

    @poss_moves.each do |mv|
      self.make_move(Move.new(King, @pos, [mv[0], mv[1]], mv[2]))
      player.solve_check[:king] += [mv] unless self.in_check
      Chess.board.revert_changes
      @checked_by = []
    end
  end

  public

  #returns true if the king is in a checkmate
  def checkmated
    unless self.in_check; return false end

    self.checkmate_defense

    return Chess.players[@color].solve_check.values.flatten(1).empty?
  end
end

#Additional monkey-patching for the Piece class
class Piece
  @piece_types = [Pawn, Rook, Knight, Bishop, Queen, King]

  @piece_strings = { 
    :black => { Pawn => "♙",   Rook => "♜",   Knight => "♞", Bishop => "♝", Queen => "♛",  King => "♚"  },
    :white => { Pawn => "♙",   Rook => "♖",   Knight => "♘", Bishop => "♗", Queen => "♕",  King => "♔"  }
  }

  @parse_dict = [['R', 'N', 'B', 'Q', 'K'], [Rook, Knight, Bishop, Queen, King]]

  def self.parse_symbols; @parse_dict[0]; end
  def self.piece_strings; @piece_strings; end

  #returns a class associated with an input character
  def self.find_class(chr)
    @parse_dict[1][@parse_dict[0].index(chr)]
  end
  
  #returns an input character associated with a class
  def self.find_class_symbol(klass)
    @parse_dict[0][@parse_dict[1].index(klass)]
  end
end

#Class hancling the player's resources and handling the correctness of their moves
class Player
  include Answers
  attr_accessor :pieces, :king, :color, :solve_check

  def initialize(color)
    @color = color
    @pieces = Hash.new { |h, k| h[k] = [] }
    @solve_check = { :king => [], :other => [] }
  end

  #checks whether the move is possible to perform
  #if it is possible, the move is performed
  #if not, returns a symbol, which gets transformed into
  #the information on why the move is not possible
  def make_move(move)
    matching_pieces = []
    en_passant_ommitement = false
    opponent = Chess.players[@color != :white ? :white : :black]

    #check whether the castling is possible
    if move.piece == Rook && (move.ending == [0,1] || move.ending == [1,0])
      if @king.has_moved || @pieces[Rook].any?(&:has_moved)
        return :impossible
      end
    end

    #if only one piece of the kind - disambiguate the beginning
    if @pieces[move.piece].length == 1
      move.beginning = @pieces[move.piece].first.pos
    end

    #if pawn - disambiguate the beginning
    #and check for en passant
    if move.piece == Pawn 
      if !move.attacking
        y_add = (@color == :white ? -1 : 1)
        move.beginning = [move.end_x, move.end_y + y_add]
        return :impossible unless (1..8).include?(move.beg_y)
      end

      if move.attacking
        ep_field = Chess.board.en_passant_target_field

        if move.end_y
           y_add = (@color == :white ? -1 : 1)
          piece = Chess.board.get_field(move.beg_x, move.end_y + y_add).piece
          if piece.class == Pawn && piece.color == @color
            matching_pieces << piece
            move.beginning = piece.pos
            #check for en passant
            if ep_field && ep_field == move.ending
              en_passant_ommitement = true
              move.en_passant = true
            end
          end
        
        else
          y_add = (@color == :white ? 1 : -1)
          
          @pieces[move.piece].each do |piece|
            next unless piece.pos[0] == move.beg_x && (1..8).include?(piece.pos[1] + y_add)
            field = Chess.board.get_field(move.end_x, piece.pos[1] + y_add)
            #check for  normal attack
            if field.piece && field.piece.color != @color
              matching_pieces << piece
            #check for en passant
            elsif ep_field && ep_field == [move.end_x, piece.pos[1] + y_add]
              matching_pieces << piece
              en_passant_ommitement = true
              move.en_passant = true
            end
          end

          case matching_pieces.size
          when 0 then return :no_pieces
          when 1 then
            piece = matching_pieces.first
            move.beginning = piece.pos
            move.ending = [move.end_x, piece.pos[1] + y_add]    
          else return :ambiguous
          end
        end
      end
    end

    #check if obstructed by one your own piece
    if Chess.board.get_field(move.end_x, move.end_y).piece &&
        Chess.board.get_field(move.end_x, move.end_y).piece.color == self.color
      return :obstructed
    end

    #if the beginning position is partial  - try to disambiguate
    if (move.beg_x && !move.beg_y) || (!move.beg_x && move.beg_y)
      idx = move.beg_x ? 0 : 1
      coord = move.beg_x || move.beg_y

      @pieces[move.piece].each do |piece|
        matching_pieces << piece if piece.pos[idx] == coord
      end

      move.beginning = matching_pieces[0].pos if matching_pieces.size == 1
    end

    #if beginning position known - check if the move is on the piece's move pattern
    if move.beg_x && move.beg_y && !en_passant_ommitement
      return :impossible unless move.piece.is_on_pattern(move, @color, false)
      piece = Chess.board.get_field(move.end_x, move.end_y).piece
      if piece && piece.color == @color && piece.class == move.piece
        matching_pieces << Chess.board.get_field(move.end_x, move.end_y).piece
      end
    end

    #check if the pawn should get promoted, while not disclosed in the move
    if move.piece == Pawn && move.promoting_to.nil? && 
      ((@color == :white && move.end_y == 8) || (@color == :black && move.end_y == 1))
      return :no_promotion
    end

    #if the move is promoting - check the correctness of the promotion
    if move.promoting_to
      unless move.piece.promotable; return :unpromotable; end
      unless move.piece.promotable_to.include?(move.promoting_to)
        return :bad_promotion
      end
    end

    #if not yet found - find pieces capable of the move
    if matching_pieces.empty?
      @pieces[move.piece].each do |piece|
        case piece.has_possible_move(move, false)
        when true then matching_pieces << piece
        end
      end
    end

    #check if more than one piece is capable of the move
    return :ambiguous if matching_pieces.size > 1

    #check if the move doesn't attack an occupied field
    if move.attacking && !Chess.board.get_field(move.end_x, move.end_y).piece &&
      !en_passant_ommitement
      return :passive
    end

    #check if the move attacks an empty field
    if !move.attacking && Chess.board.get_field(move.end_x, move.end_y).piece &&
      Chess.board.get_field(move.end_x, move.end_y).piece.color != self.color
      return :attacking
    end

    #check if there are no pieces capable of the move
    return :no_pieces if matching_pieces.size == 0

    #check if the king is in check and the move does not solve the check
    if @king.in_check
      mode = (move.piece == King ? :king : :other)
      return :checkdefense unless @solve_check[mode].find_index([move.end_x, move.end_y, (move.attacking ? :attacking : :passive)])
    end

    #make the move
    piece = matching_pieces[0]
    piece.make_move(move)

    #check if the move reveals the king for a check
    if @king.in_check
      Chess.board.revert_changes
      return :check_vulnerable
    end

    opp_king_checked = opponent.king.in_check

    #check if the move declares a check, but does not result in a check
    if !opp_king_checked && move.checking
      Chess.board.revert_changes
      return :not_checking
    end

    #check if the move results in a check, but does not declare a check
    if opp_king_checked && !move.checking
      Chess.board.revert_changes
      return :check 
    end

    opp_king_checkmated = opponent.king.checkmated

    #check if the move declares a checkmate, but does not result in a checkmate
    if !opp_king_checkmated && move.checkmating
      Chess.board.revert_changes
      return :not_checkmating
    end

    #check if the move result in a checkmate, but does not declade it
    if opp_king_checkmated
      unless move.checkmating
        Chess.board.revert_changes
        return :checkmate
      else
        return :won
      end
    end

    #if it passed all the conditions, pass the move as correct
    return nil
  end

  #true, if the player accepts the draw proposal
  def consider_draw
    yes_no_question("Your opponent asked you for a draw. Do you accept this proposal")
  end

  #empties the @solve_check and the king's @checked_by, since the check has been resolved
  def reset_check
    @solve_check = { :king => [], :other => [] }
    @king.checked_by = []
  end

  #removes the piece from the player's piece hash
  def delete_piece(piece)
    @pieces[piece.class].delete(piece)
  end
end

#The main class of the game.
#Manages the course of the game.
class Chess
  include DataManagement, Answers

  class << self
    attr_accessor :board, :players
  end

  attr_accessor :turn_count, :game_state, :stalemate_danger
  attr_accessor :history

  public
  def initialize
    self.class.players = {:white => Player.new(:white), :black => Player.new(:black)}
    self.class.board = Board.new
    @turn_count = 1
    @tutorial_done = false
    @history = [[]]
  end
  
  #the main loop of the game: setup -> turns -> finalize
  def play
    self.setup
    @game_state = nil
    while(@game_state.nil?)
      self.turn_setup
      self.turn
      @turn_count += 1
      self.turn_reset
    end
    self.finalize
  end

  private

  #manages the main menu, which gives an ability to
  #1. play
  #2. manage the saves
  #3. exit the game
  def setup
    system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
    
    @game_state = :setup
    setup_signal_trap
    done = false
    @save_loaded = false
    until done
      case mult_ans_question("Welcome to the game of chess!", ['play', 'saves', 'exit'])
      when 'play' then
        return if self.auto_save_rescue
        Chess.board.set unless @save_loaded
        done = true
      when 'saves' then
        self.saves_options
      when 'exit' then
        popup("Game will close momentarily.", 1)
        popup("Game closed.", 1)
        system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
        exit
      end
    end
  end

  #sets the current player and the opponent variables and
  #checks for stalemate (a situation when the current player has no correct moves)
  def turn_setup
    if @turn_count % 2 == 1
      @curr_player = Chess.players[:white]
      @opponent    = Chess.players[:black]
    else
      @curr_player = Chess.players[:black]
      @opponent    = Chess.players[:white]
    end

    @stalemate_danger = true
    @curr_player.pieces.values.each do |typed_pieces|
      typed_pieces.each do |piece|
        piece.get_possible_moves
        @stalemate_danger = false if piece.poss_moves.any?
      end
    end
  end

  #manages the turn actions
  def turn
    #if stalemate was detected, change the game state and exit
    if @stalemate_danger
      @game_state = :stalemate
      return
    end

    #if this is the first game, show the tutorial
    unless @tutorial_done
      puts "The game uses chess algebraic notation to perform movements."
      puts "The game also possesses a few commands to help with the game experiance."
      puts "Insert 'help' to get the list of all possible commands.\n\n"
      puts "*press any button to continue*"
      gets
      @tutorial_done = true
    end

    loop do
      #wipe the console
      system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
      #print board
      puts Chess.board

      print @curr_player.color == :white ? "White's turn: " : "Black's turn: "
      puts "(enter a command or make a move): "

      str = gets.chomp
      print "\e[1A\e[2K"

      #manage the player commands (expanation in the help case)
      case str
      when "draw?"
        if @opponent.consider_draw; @game_state = :draw end
      
      when "surrender"
        if yes_no_question("Are you sure you want to surrender?")
          puts @opponent.color != :white ? "White surrenders." : "Black surrenders."
          @game_state = (@opponent.color == :white ? :won_white : :won_black)
          sleep(2)
          break
        end
      when "help"
        system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
        puts "Available commands : 
        • draw? — asks your opponent for a draw
        • surrender — ends the game with a loss
        • help — shows all available commands
        • history — prints the records of all the moves performed by both players
        • exit — exit to the main menu"
        puts "*press any button to close*"
        gets
      when "save" then save_to
      when "history" then print_history
      when "exit" then
        if yes_no_question("Do you wish to save the game before exiting?") && yes_no_question("Are you sure?")
          save_to
          delete_save(0)
        end
        self.play
        exit
      #if neither of the inputs is a player command, the input gets redirected to the move parsing
      else 
        result = self.parse_move(str)
        case result
        when :won_white, :won_black then update_history(str); @game_state = result; break
        when :end_turn then update_history(str); break
        end
      end
    end
  end

  #resets some variables before the next turn
  def turn_reset
    @curr_player.pieces.values.each do |typed_pieces|
      typed_pieces.each do |piece|
        piece.turn_reset
      end
    end
    @curr_player.reset_check
    self.auto_save
  end

  #Summerizes the game
  #and returns the user to the main menu
  def finalize
    puts Chess.board
    case @game_state
    when :won_white then puts "White won the game."
    when :won_black then puts "Black won the game."
    when :draw      then puts "The game ended up in a draw."
    when :stalemate then puts "The game ended up with a stalemate."
    end

    print_history
    delete_save(0)

    new_instance = Chess.new
    new_instance.play
  end

  #handles the movement commands and the error messages assosciated with the incorrect moves
  def parse_move(str)
    move = Move.new
    if move.parse_move(str)
      result = @curr_player.make_move(move)
      case result
      when :won then return @curr_player.color == :white ? :won_white : :won_black
      when :checkdefense      then popup("This move does not stop the opponent's check.", 3)
      when :impossible        then popup("The movement of the piece is not allowed by the rules.", 3)
      when :unpromotable      then popup("The pieces of this kind cannot undergo promotion.", 3)
      when :bad_promotion     then popup("The piece cannot get promoted into the piece of the choosen kind.", 3)
      when :no_promotion      then popup("The piece requires a promotion goal to enter this space.", 3)
      when :ambiguous         then popup("There are multiple pieces capable of performing the move. Specify which one should perform the move.", 3)
      when :obstructed        then popup("The field in obstucted by another piece of yours.", 3)
      when :attacking         then popup("The passive move atacks an opponent's piece.", 3)
      when :passive           then popup("The attacking move doesn't attack any pieces.", 3)
      when :no_pieces         then popup("There are no pieces capable of this movement.", 3)
      when :cant_promote      then popup("The piece cannot get promoted during this move.", 3)
      when :check             then popup("The move results in an undeclared check.", 3)
      when :not_checking      then popup("The move does not result in a check.", 3)
      when :checkmate         then popup("The move results in an undeclared checkmate.", 3)
      when :not_checkmating   then popup("The move does not result in a checkmate.", 3)
      when :check_vulnerable  then popup("The move would reveal the player's king.", 3)
      else :end_turn
      end
    else
      popup "Unrecognised commend."
    end
  end

  #updates the history of the moves performed by both players
  def update_history(str)
    case history.last.length
    when 0, 1 then history.last << str
    when 2 then
      if history.last[1].nil?
        history.last[1] = str
      else history << [str]
      end
    end
  end

  #prints the records of the moves performed during the game
  def print_history
    system(RUBY_PLATFORM =~ /win32|mingw|cygwin/ ? "cls" : "clear")
    if history.first.empty?
      puts "There are no records for this game."
      puts "*press any button to close*"
      gets
      return
    end

    puts "Game records: "
    sleep(1)
    @history.each_with_index do |record, idx|
      print (idx + 1).to_s + ". "
      print record[0] if record[0]
      print "\t" + record[1] if record[1]
      puts
    end
    puts "*press any button to close*"
    gets
  end
end

chess = Chess.new
chess.play