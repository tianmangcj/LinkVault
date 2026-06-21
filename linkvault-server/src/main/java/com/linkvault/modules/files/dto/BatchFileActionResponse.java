package com.linkvault.modules.files.dto;

import java.util.List;

public record BatchFileActionResponse(
        int total,
        int succeeded,
        int failed,
        List<BatchFileActionItemVM> items
) {

    public static BatchFileActionResponse from(List<BatchFileActionItemVM> items) {
        var succeeded = (int) items.stream().filter(BatchFileActionItemVM::success).count();
        return new BatchFileActionResponse(
                items.size(),
                succeeded,
                items.size() - succeeded,
                List.copyOf(items)
        );
    }
}
