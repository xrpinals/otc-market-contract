-- N stands for Normal (Market State)
-- C stands for Closed (Market State)
type MarketState = 'N' | 'C'

type Storage = {
    base: string,
    quote: string, 
    state: string,
    owner: string,
	order_idx: int,
	assets_map: Map<string>,   -- Key: User Address   Value: assets json str
	sell_orders: Map<string>    -- Key: Order Idx    Value: order info
} 

var M = Contract<Storage>()


function M:init()   
    self.base_symbol = "XPS"
    self.quote_symbol = "BTC"
    self.storage.state = 'N'
    self.storage.owner = caller_address
    self.storage.order_idx = 0
	self.storage.assets_map = {}
	self.storage.sell_orders = {} 
end


-- Check Market State (Must be Normal State)
let function check_market_state(M: table)
    if M.storage.state ~= 'N' then
        return error("State Error, MarketState: " .. tostring(M.storage.state))
    end
end


-- Check Invoker (Must be common user /Must not be contract)
let function check_caller_frame_valid(M: table)
    let prev_contract_id = get_prev_call_frame_contract_address()
    if (not prev_contract_id) or (#prev_contract_id < 1) then
        return true
    else
        return error("Can not invoked by contract")
    end
end


-- If you want to sub it, use negative amount
let function add_asset_amount(M: table, user: string, symbol: string, amount: int)
    var user_assets_str = self.storage.assets_map[user]
    var user_assets = {}
    var after_amount = 0
    if (user_assets_str == nil) then
        if (amount <= 0) then
            return error("Asset amount can not be negative")
        else
            after_amount = amount
        end
    else
        user_assets = json.loads(user_assets_str)
        let previous_amount = user_assets[symbol]
        if (previous_amount == nil) then
            if (amount <= 0) then
                return error("Asset amount can not be negative")
            else
                after_amount = amount
            end
        else
            after_amount = previous_amount + amount
            if (after_amount <= 0) then 
                return error("Asset amount can not be negative")
            end
        end
    end

    user_assets[symbol] = after_amount
    let r = json.dumps(user_assets)
    self.storage.asset_map[user] = r
end


return M
