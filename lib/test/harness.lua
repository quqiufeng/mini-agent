local H = { pass = 0, fail = 0 }
function H.ok(cond, msg)
    if cond then
        H.pass = H.pass + 1
        io.write("ok   ", msg or "", "\n")
    else
        H.fail = H.fail + 1
        io.write("FAIL ", msg or "", "\n")
    end
end
function H.eq(a, b, msg)
    H.ok(tostring(a) == tostring(b), (msg or "") .. " (" .. tostring(a) .. " == " .. tostring(b) .. ")")
end
function H.done()
    io.write(string.format("\n%d passed, %d failed\n", H.pass, H.fail))
    os.exit(H.fail == 0 and 0 or 1)
end
return H
