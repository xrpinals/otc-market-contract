-- N stands for Normal (Market State)
-- C stands for Closed (Market State)

-- type MarketState = 'N' | 'C'
type Contract<T> = {
    storage: T
}

type Storage = {
    base_symbol: string,
    quote_symbol: string, 
    state: string,
    owner: string,
    fee_rate: int,
    top_order_index: int,
    orders_indexes: Array<string>
} 

var M = Contract<Storage>()


function M:init()   
    self.storage.base_symbol = ""
    self.storage.quote_symbol = ""
    self.storage.state = 'C'
    self.storage.owner = caller_address
    self.storage.fee_rate = 0
    self.storage.top_order_index = 1
    self.storage.orders_indexes = []
end


-- Check Market State (Must be Normal State)
let function check_market_state(M: table)
    if M.storage.state ~= 'N' then
        return error("State Error, MarketState: " .. tostring(M.storage.state))
    end
end


-- Check Market State Close (Must be Close State)
let function check_market_state_close(M: table)
    if M.storage.state ~= 'C' then
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


offline function M:market_name(_: string)
    return self.storage.base_symbol .. "-" .. self.storage.quote_symbol
end


offline function M:state(_: string)
    return self.storage.state
end


offline function M:owner(_: string)
    return self.storage.owner
end


offline function M:top_order_index(_: string)
    return self.storage.top_order_index
end


offline function M:order_count(param_str: string)
    return #self.storage.orders_indexes
end


-- from_idx,page_count
offline function M:sell_orders(param_str: string)
    let params = string.split(param_str, ',')
    if (not params) or (#params ~= 2) then
        return error("Params Error: invalid params")
    end

    let from_idx = tointeger(params[1])
    let page_count = tointeger(params[2])
    var end_idx = from_idx + page_count

    if end_idx >= #self.storage.orders_indexes then
        end_idx = #self.storage.orders_indexes
    end

    let orders: Array<string> = []
    for i = from_idx, end_idx do
        let order_idx = tostring(self.storage.orders_indexes[i])
        let r = fast_map_get("sell_orders", order_idx)
        orders[#orders + 1] = r
    end

    return orders
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

    if (not sell_symbol) or (#sell_symbol < 1) then
         return error("Params Error: invalid sell_symbol")
    end

    if (sell_symbol ~= self.storage.base_symbol) and (sell_symbol ~= self.storage.quote_symbol) then
        return error("Params Error: invalid sell_symbol")
    end

    let params = string.split(param_str, ',')
    if (not params) or (#params ~= 2 and #params ~= 3) then
        return error("Params Error: invalid params")
    end

    var sell_order = {}
    if (#params == 3) then
        if (params[1] ~= "SELL") then
            return error("Params Error: invalid params")
        end

        let buy_symbol = tostring(params[2])
        let buy_amount = tointeger(params[3])

        if (buy_symbol ~= self.storage.base_symbol) and (buy_symbol ~= self.storage.quote_symbol) then
            return error("Params Error: invalid buy_symbol")
        end

        if (sell_symbol == buy_symbol) then
            return error("Params Error: sell_symbol must not same with buy_symbol")
        end

        if (not buy_amount) or (buy_amount <= 0) then
            return error("Params Error: buy_amount must greater than 0")
        end

        
        sell_order["seller"] = caller_address
        sell_order["sell_symbol"] = sell_symbol
        sell_order["sell_amount"] = tostring(sell_amount)
        sell_order["buy_symbol"] = buy_symbol
        sell_order["buy_amount"] = tostring(buy_amount)
        sell_order["order_index"] = tostring(self.storage.top_order_index)
        let r = json.dumps(sell_order)
        
        let event_str = caller_address .. "," .. tostring(self.storage.top_order_index) .. "," ..  tostring(sell_symbol) .. "," .. tostring(sell_amount) .. "," ..  tostring(buy_symbol) .. "," .. tostring(buy_amount)
        emit PlaceOrder(event_str)

        fast_map_set("sell_orders", tostring(self.storage.top_order_index), tostring(r))
        self.storage.orders_indexes[#self.storage.orders_indexes + 1] = tostring(self.storage.top_order_index)
        self.storage.top_order_index = self.storage.top_order_index + 1
    else
        if (params[1] ~= "BUY") then
            return error("Params Error: invalid params")
        end

        let order_idx = tostring(params[2])
        var found = false
        for k, v in pairs(self.storage.orders_indexes) do
            if v == order_idx then
                found = true
                break
            end
        end

        if (found == false) then
            return error("Params Error: invalid order_idx")
        end

        let rr = fast_map_get("sell_orders", order_idx) or ""
        sell_order = totable(json.loads(tostring(rr)))

        if (sell_order == nil) then
            return error("Params Error: invalid order_idx")
        end

        if (sell_order["seller"] == caller_address) then
            return error("Params Error: can not buy order placed by yourself")
        end

        if (sell_symbol == sell_order["buy_symbol"]) and (tostring(sell_amount) == sell_order["buy_amount"]) then
            let need_transfer_fee = safemath.toint(safemath.div(safemath.mul(safemath.bigint(sell_amount), safemath.bigint(self.storage.fee_rate)), safemath.bigint(10000)))
            let need_transfer_amount = sell_amount - need_transfer_fee

            -- transfer to seller
            let res1 = transfer_from_contract_to_address(tostring(sell_order["seller"]), sell_symbol, need_transfer_amount)
            if res1 ~= 0 then
                return error("Transfer asset " .. sell_symbol .. " to " .. tostring(sell_order["seller"]) .. " error, code: " .. tostring(res1))
            end

            let event_str1 = tostring(sell_order["seller"]) .. "," ..  tostring(sell_order["sell_symbol"]) .. "," .. tostring(sell_order["sell_amount"]) .. "," ..  tostring(sell_symbol) .. "," .. tostring(sell_amount)
            emit Exchange(event_str1)

            if need_transfer_fee > 0 then
                -- transfer to owner
                let res_fee = transfer_from_contract_to_address(self.storage.owner, sell_symbol, need_transfer_fee)
                if res_fee ~= 0 then
                    return error("Transfer fee " .. sell_symbol .. " to " .. self.storage.owner .. " error, code: " .. tostring(res_fee))
                end

                let event_fee = tostring(sell_order["seller"]) .. "," .. tostring(sell_symbol) .. "," .. tostring(need_transfer_fee)
                emit ExchangeFee(event_fee)
            end

            -- transfer to buyer
            let res2 = transfer_from_contract_to_address(caller_address, tostring(sell_order["sell_symbol"]), tointeger(sell_order["sell_amount"]))
            if res2 ~= 0 then
                return error("Transfer asset " .. tostring(sell_order["sell_symbol"]) .. " to " .. caller_address .. " error, code: " .. tostring(res2))
            end

            let event_str2 = caller_address .. "," ..  tostring(sell_symbol) .. "," .. tostring(sell_amount) .. "," ..  tostring(sell_order["sell_symbol"]) .. "," .. tostring(sell_order["sell_amount"])
            emit Exchange(event_str2)

            -- delete order
            for k, v in pairs(self.storage.orders_indexes) do
                if v == order_idx then
                    table.remove(self.storage.orders_indexes, k)
                    break
                end
            end
            fast_map_set("sell_orders", order_idx, nil)
        else
            return error("Params Error: your sell_symbol/sell_amount not match with buy_symbol/buy_amount of the order")
        end
    end
end


function M:cancel_order(order_idx: string)
    check_market_state(self)
    check_caller_frame_valid(self)

    let r = fast_map_get("sell_orders", order_idx)
    let sell_order = totable(json.loads(tostring(r)))

    if(sell_order == nil) then
        return error("Params Error: invalid order_idx")
    end

    if (sell_order["seller"] ~= caller_address and sell_order["seller"] ~= self.storage.owner) then
        return error("Params Error: only allow to cancel order placed by yourself or administrator of the market")
    end

    -- transfer to seller
    let res = transfer_from_contract_to_address(tostring(sell_order["seller"]), tostring(sell_order["sell_symbol"]), tointeger(sell_order["sell_amount"]))
    if res ~= 0 then
        return error("Transfer asset " .. tostring(sell_order["sell_symbol"]) .. " to " .. tostring(sell_order["seller"]) .. " error, code: " .. tostring(res))
    end

    let event_str = tostring(sell_order["seller"]) .. "," ..  tostring(sell_order["sell_symbol"]) .. "," .. tostring(sell_order["sell_amount"])
    emit CancelOrder(event_str)

    -- delete order
    for k, v in pairs(self.storage.orders_indexes) do
        if v == order_idx then
            table.remove(self.storage.orders_indexes, k)
            break
        end
    end
    fast_map_set("sell_orders", order_idx, nil)
end


function M:set_fee_rate(fee_rate_str: string)
    check_market_state(self)
    check_caller_frame_valid(self)

    if self.storage.owner ~= caller_address then
        return error("Permission denied")
    end

    let fee_rate = tointeger(fee_rate_str)
    if (fee_rate < 0) or (fee_rate > 10000) then
        return error("Params Error: invalid fee_rate")
    end

    self.storage.fee_rate = fee_rate

    let event = tostring(fee_rate)
    emit FeeRateChanged(event)
end


function M:open_market(param_str: string)
    check_market_state_close(self)
    check_caller_frame_valid(self)

    let params = string.split(param_str, ',')
    if (not params) or (#params ~= 2) then
        return error("Params Error: invalid params")
    end

    let base_symbol = tostring(params[1])
    let quote_symbol = tostring(params[2])

    if (base_symbol == "") or (quote_symbol == "") then
        return error("Params Error: invalid params")
    end 

    if (base_symbol == quote_symbol) then
        return error("Params Error: base_symbol can not be same with quote_symbol")
    end

    if (self.storage.base_symbol ~= "") or (self.storage.quote_symbol ~= "") then
        return error("Params Error: open_market can not invoked twice")
    end 

    if self.storage.owner ~= caller_address then
        return error("Permission denied")
    end
    
    self.storage.base_symbol = base_symbol
    self.storage.quote_symbol = quote_symbol
    self.storage.state = 'N'

    let event = self.storage.base_symbol .. "-" .. self.storage.quote_symbol
    emit MarketOpened(event)
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
    check_market_state_close(self)
    check_caller_frame_valid(self)

    if self.storage.owner ~= caller_address then
        return error("Permission denied")
    end
    
    if (self.storage.base_symbol == "") or (self.storage.quote_symbol == "") then
        return error("You must invoke open_market first")
    end 

    self.storage.state = 'N'

    let event = self.storage.base_symbol .. "-" .. self.storage.quote_symbol
    emit MarketReopened(event)
end


return M
