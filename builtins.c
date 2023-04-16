/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   builtins.c                                         :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mazaroua <mazaroua@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/04/08 16:09:06 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/14 22:28:57 by mazaroua         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

void ft_cd(char *path, t_env_list **env_list)
{
    int i;

    if (path == NULL || path[0] == '~')
    {
        char *home_dir = get_home_var(env_list);
        if (!home_dir)
        {
            perror("Error: HOME directory not found");
            return;
        }
        i = chdir(home_dir);
    }
    else
    {
        i = chdir(path);
        if (i == -1)
        {
            write (2, "minishell: ", ft_strlen("minishell: "));
            write (2, path , ft_strlen(path));
            write (2, ": No such file or directory\n", ft_strlen(": No such file or directory\n"));
        }
    }
}

void    ft_pwd(void)
{
   char cwd[2000];

   if (getcwd(cwd, sizeof(cwd)) != NULL)
	   ft_putstr(cwd);
   else
   {
	   perror("getcwd() error");
      exit(1);
    }
	ft_putstr("\n");
    exit(0);
}
