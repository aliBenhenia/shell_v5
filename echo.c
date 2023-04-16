#include "minishell.h"

// static void    ft_putstr(char *s)
// {
//     int i;

//     i = 0;
//     while (s[i])
//     {
//         write(1,&s[i],1);
//         i++;
//     }
// }
int count_len_of_str(char *s[])
{
    int i;

    i = 0;
    while (s[i])
    {
        i++;
    }
    return i;
}
int is_n(char *str)
{
    int i;

    i = 0;
    if(str == NULL)
        return 0;
    if (str[i] == '-')
        i++;
    while (str[i] && str[i] != 32)
    {
        if (str[i] != 'n')
            return (0);
        i++;
    }
    return (1);
}
int if_more_n(char *s)
{
    int i;

    i = 0;
    if(s[i] != '-')
        return 1;
    while(s[i])
    {
        if(s[i] != '-' && s[i] != 'n')
            return 1;
        i++;
    }
    return 0;
}
void    ft_echo(char **str)
{
    int f;
    int len;
    int i;

    f = 0;
    i = 1;
    if (str[1] == NULL)
    {
        ft_putstr("\n");
        return ;
    }
    while (is_n(str[i]))
    {
        f = 1;
        if(if_more_n(str[i]))
            break;
        i++;
    }
    if(i > 2)
        f = 1;
    len = count_len_of_str(str);
    while (i < len )
    {
       ft_putstr(str[i]);
       if (str[i + 1])
         ft_putstr(" ");
       i++;
    }
    if (f == 0)
        ft_putstr("\n");
}