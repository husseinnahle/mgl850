import { useEffect, useState } from "react";

export function useTimedMessage(duration = 3000): [string, (message: string) => void] {
    const [message, setMessage] = useState("");

    useEffect(() => {
        if (!message) return;

        const timeoutId = window.setTimeout(() => setMessage(""), duration);
        return () => window.clearTimeout(timeoutId);
    }, [duration, message]);

    return [message, setMessage];
}
