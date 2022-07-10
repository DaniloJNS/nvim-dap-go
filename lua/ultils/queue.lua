local Queue = {}

function Queue:new(_)
  self.values = {}

  return self
end

function Queue:push(value)
  table.insert(self.values, #self.values + 1, value)
end

function Queue:pop()
  table.remove(self.values, #self.values)
end

return Queue
