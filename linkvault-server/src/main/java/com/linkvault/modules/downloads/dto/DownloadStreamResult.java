package com.linkvault.modules.downloads.dto;

import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

public record DownloadStreamResult(
        String fileName,
        long sizeBytes,
        long offset,
        String mimeType,
        StreamingResponseBody body
) {
}
