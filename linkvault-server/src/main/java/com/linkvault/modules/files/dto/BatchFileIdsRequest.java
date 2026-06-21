package com.linkvault.modules.files.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

public record BatchFileIdsRequest(
        @NotEmpty
        @Size(max = 10)
        List<@NotNull UUID> fileIds
) {
}
