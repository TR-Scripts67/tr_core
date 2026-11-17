return {
    number = function() return nil end,
    notify = function(src, note)
        TR.notify.send(src, { title = note.title, description = note.text, type = 'inform' })
    end,
}
