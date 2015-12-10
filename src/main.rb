# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
require 'json'
require 'benchmark'

# Variable declarations
silkroad = nil
db = nil
highest_block = 0
hash_array = []

def start_up_rpc
  paycoinURI = URI::HTTP.build(['ligerzero459:k3ep48dl_s', '127.0.0.1', 9001, nil, nil, nil])
  silkroad = Silkroad::Client.new paycoinURI, {}

  silkroad
end

def start_up_db
  db = SQLite3::Database.open('../XPYBlockchain.sqlite')

  # Create tables if they don't exist
  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='blocks'")
  puts 'exists: ' + exists.to_s
  if exists.length == 0
    puts 'creating table'
    db.execute("CREATE TABLE IF NOT EXISTS `blocks` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `hash`	TEXT NOT NULL UNIQUE,
      `height`	INTEGER NOT NULL UNIQUE,
      `blockTime`	TEXT,
      `mint`	REAL,
      `previousBlockHash`	TEXT,
      `flags`	TEXT
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='raw_blocks'")
  if exists.length == 0
    db.execute("CREATE TABLE `raw_blocks` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `height`	INTEGER,
      `raw`	BLOB
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'")
  if exists.length == 0

  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='raw_transactions'")
  if exists.length == 0
    db.execute("CREATE TABLE `raw_blocks` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `txid`	TEXT,
      `raw`	BLOB
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='inputs'")
  if exists.length == 0

  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='outputs'")
  if exists.length == 0

  end

  # return completed db
  db
end

silkroad = start_up_rpc
# db = start_up_db

hash = silkroad.rpc 'getblockhash', 2554
block = silkroad.rpc 'getblock', hash

puts JSON.pretty_generate(block)

raw_txs = silkroad.batch do
  block['tx'].each do |tx|
    rpc 'getrawtransaction', tx
  end
end

decoded_txs = silkroad.batch do
  raw_txs.each do |raw_tx|
    rpc 'decoderawtransaction', raw_tx['result']
  end
end

puts decoded_txs[0].fetch("result")
vin = decoded_txs[0].fetch("result").fetch("vin")

if vin[0]['coinbase'] != nil
  puts vin[0]['coinbase']
else
  puts vin[0]['txid']
end

# Code for multiple blocks
# Will be updated once single block and transactions are read into DB

# block_count =  silkroad.rpc 'getblockcount'
# puts block_count
#
# (highest_block..block_count).each do |block_num|
#   hash = silkroad.rpc 'getblockhash', block_num
#   hash_array.push(hash)
#   puts block_num.to_s + " | " + hash
# end
