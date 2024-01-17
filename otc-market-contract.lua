-- N stands for Normal (Market State)
-- C stands for Closed (Market State)
type MarketState = 'N' | 'C'

type Storage = {
    base: string,
    quote: string, 
    state: string,
    owner: string,
	order_index: int,
    orders_count: int,
	sell_orders: Map<string>    -- Key: Order Idx    Value: order info
} 

var M = Contract<Storage>()


function M:init()   
    self.base_symbol = "XPS"
    self.quote_symbol = "BTC"
    self.storage.state = 'N'
    self.storage.owner = caller_address
    self.storage.order_index = 1
    self.storage.order_count = 0
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


offline function M:market_pair(_: string)
    return self.storage.base_symbol .. "-" .. self.storage.quote_symbol
end


offline function M:state(_: string)
    return self.storage.state
end


offline function M:owner(_: string)
    return self.storage.owner
end


offline function M:order_index(_: string)
    return self.storage.order_index
end


offline function M:order_count(_: string)
    return self.storage.order_count
end


offline function M:sell_orders(_: string)

    return sell_orders_str
end


function M:on_deposit_asset(json_str: string)
    check_market_state(self)
    check_caller_frame_valid(self)

    let json_arg = json.loads(json_str)
    let sell_amount = tointeger(json_arg.num)
    let sell_symbol = tostring(json_arg.symbol)
    -- param: SELL,WantToBuyAssetSymbol,WantToBuyAssetAmount
    -- param: BUY,OrderIdx
    let param_str = tostring(json_arg.param)

	if (not sell_amount) or (sell_amount <= 0) then
		 return error("Params Error: sell_amount must greater than 0")
	end

	if (not symbol) or (#symbol < 1) then
		 return error("Params Error: invalid sell_symbol")
	end

    if (symbol ~= self.storage.base_symbol) and (symbol ~= self.storage.quote_symbol) then
        return error("Params Error: invalid sell_symbol")
    end

    let params = string.split(param_str, ',')
    if (not params) or (#params ~= 2 and #params ~= 3) then
        return error("Params Error: invalid params)
    end

    if (#params ~= 3) then
        if (params[1] ~= "SELL" then
            return error("Params Error: invalid params)
        end

        let buy_symbol = params[2]
        let buy_amount = tointeger(params[3])
        
        if (sell_symbol == buy_symbol) then
            return error("Params Error: sell_symbol must not same with buy_symbol")
        end

        if (not buy_amount) or (buy_amount <= 0) then
            return error("Params Error: buy_amount must greater than 0")
        end

        var sell_order = {}
        sell_order["seller"] = caller_address
        sell_order["sell_symbol"] = sell_symbol
        sell_order["sell_amount"] = to_string(sell_amount)
        sell_order["buy_symbol"] = buy_symbol
        sell_order["buy_amount"] = to_string(buy_amount)
        let r = json.dumps(sell_order)
        
        let event_str = caller_address .. "," ..  tostring(sell_symbol) .. "," .. to_string(sell_amount) .. "," ..  tostring(buy_symbol) .. "," .. to_string(buy_amount)
        emit PlaceOrder(event_str)

        fast_map_set(sell_orders, to_string(self.storage.order_index), r)
        self.storage.order_index = self.storage.order_index + 1
    else
        if (params[1] ~= "BUY" then
            return error("Params Error: invalid params)
        end

        let order_idx = params[2]
        let r = fast_map_get(sell_orders, order_idx)
        sell_order = totable(json.loads(r))

        if(sell_order == nil) then
			return error("Params Error: invalid order_idx")
		end

        if (sell_order["seller"] == caller_address) then
			return error("Params Error: can not buy order placed by yourself")
		end

        if (sell_symbol == sell_order["buy_symbol"]) and (to_string(sell_amount) == sell_order["buy_amount"]) then
            -- transfer to seller
            let res1 = transfer_from_contract_to_address(sell_order["seller"], sell_symbol, sell_amount)
            if res1 ~= 0 then
                return error("Transfer asset " .. sell_symbol .. " to " .. sell_order["seller"] .. " error, code: " .. tostring(res1))
            end

            let event_str1 = sell_order["seller"] .. "," ..  tostring(sell_order["sell_symbol"]) .. "," .. to_string(sell_order["sell_amount"]) .. "," ..  tostring(sell_symbol) .. "," .. to_string(sell_amount)
            emit Exchange(event_str1)

            -- transfer to buyer
            let res2 = transfer_from_contract_to_address(caller_address, sell_order["sell_symbol"], tointeger(sell_order["sell_amount"]))
            if res2 ~= 0 then
                return error("Transfer asset " .. sell_order["sell_symbol"] .. " to " .. caller_address .. " error, code: " .. tostring(res2))
            end

            let event_str2 = caller_address .. "," ..  tostring(sell_symbol) .. "," .. to_string(sell_amount) .. "," ..  sell_order["sell_symbol"] .. "," .. to_string(sell_order["sell_amount"])
            emit Exchange(event_str2)

            -- delete order
            fast_map_set(sell_orders, order_idx, nil)
        else
            return error("Params Error: your sell_symbol/sell_amount not match with buy_symbol/buy_amount of the order")
        end
    end
end


function M:cancel_order(order_idx: string)
    check_market_state(self)
    check_caller_frame_valid(self)

    let r = fast_map_get(sell_orders, order_idx)
    sell_order = totable(json.loads(r))

    if(sell_order == nil) then
        return error("Params Error: invalid order_idx")
    end

    if (sell_order["seller"] ~= caller_address and sell_order["seller"] ~= self.storage.owner) then
        return error("Params Error: only allow to cancel order placed by yourself or administrator of the market")
    end

    -- transfer to seller
    let res = transfer_from_contract_to_address(sell_order["seller"], sell_order["sell_symbol"], tointeger(sell_order["sell_amount"]))
    if res ~= 0 then
        return error("Transfer asset " .. sell_order["sell_symbol"] .. " to " .. sell_order["seller"] .. " error, code: " .. tostring(res))
    end

    let event_str = sell_order["seller"] .. "," ..  tostring(sell_order["sell_symbol"]) .. "," .. to_string(sell_order["sell_amount"])
    emit CancelOrder(event_str)

    -- delete order
    fast_map_set(sell_orders, order_idx, nil)
end


function M:close_market()
	check_market_state(self)
    check_caller_frame_valid(self)

    if self.storage.owner ~= caller_address then
        return error("Permission denied")
    end
    
	self.storage.state = 'C'

    let event = self.storage.base_symbol .. "-" .. self.storage.quote_symbol
	emit MarketClosed(event)
end


function M:reopen_market()
	check_market_state(self)
    check_caller_frame_valid(self)

    if self.storage.owner ~= caller_address then
        return error("Permission denied")
    end
    
	self.storage.state = 'N'

    let event = self.storage.base_symbol .. "-" .. self.storage.quote_symbol
	emit MarketReopened(event)
end


return M
