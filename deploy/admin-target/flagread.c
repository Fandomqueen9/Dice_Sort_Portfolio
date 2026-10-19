#include <stdio.h>

int main() {
    FILE *fp = fopen("/root/flag.txt", "r");
    if (fp == NULL) {
        fprintf(stderr, "Error: cannot open /root/flag.txt\n");
        return 1;
    }
    
    char buffer[256];
    if (fgets(buffer, sizeof(buffer), fp) != NULL) {
        printf("%s", buffer);
    }
    fclose(fp);
    return 0;
}
