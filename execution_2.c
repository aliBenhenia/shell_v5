/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   execution_2.c                                      :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mazaroua <mazaroua@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/04/09 14:07:54 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/13 16:01:06 by mazaroua         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

int	builtins(char	*cmd)
{

	if (!ft_strcmp(cmd, "echo"))
		return (1);
	if (!ft_strcmp(cmd, "pwd"))
		return (2);
	if (!ft_strcmp(cmd, "export"))
		return (3);
	if (!ft_strcmp(cmd, "env"))
		return (4);
	return (0);
}
void    print_env(t_env_list *list)
{
    t_env_list *head = list;
    while (head)
    {
        if(ft_strcmp(head->value,"") == 0)
            printf("%s\n",head->name);
        else
            printf("%s=\"%s\"\n",head->name,head->value);
            head = head->next;
     }
}
void	exec_builtins(char	**str, t_env_list **env_list, int code, t_export **export)
{
    if (code == 1)
    {
        ft_echo(str);
        exit(0);
    }
	if (code == 2)
    {
		ft_pwd();
        exit(0);
    }
	else if (code == 3)
    {
        do_export(str,export,env_list);
        exit(0);
    }
    else if(code == 4)
    {
        print_env(*env_list);
      
        exit(0);
    }

}

int main_builtins(t_cmd_line **cmd_line)
{
    if ((*cmd_line) && (*cmd_line)->str[0])
    {
        if (!ft_strcmp((*cmd_line)->str[0], "cd"))
            return (1);
        if (!ft_strcmp((*cmd_line)->str[0], "export") && (*cmd_line)->str[1] != NULL)
            return (1);
        if (!ft_strcmp((*cmd_line)->str[0], "unset"))
            return (1);
    }
    return (0);
}

void    execute_builtins(t_cmd_line **cmd_line, t_env_list **env_list,t_export **export_list)
{
    if (!ft_strcmp((*cmd_line)->str[0], "cd"))
        ft_cd((*cmd_line)->str[1], env_list);
    if (!ft_strcmp((*cmd_line)->str[0], "export"))
       do_export((*cmd_line)->str,export_list,env_list);
    if (!ft_strcmp((*cmd_line)->str[0], "unset"))
        do_unset((*cmd_line)->str,export_list,env_list);
}