function togglewg
    set output (sudo wg)
    if test -n "$output"
        wgdn
    else
        wgup
    end
end
