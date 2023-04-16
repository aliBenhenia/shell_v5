/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   execution.c                                        :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mazaroua <mazaroua@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/04/08 15:38:01 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/14 22:33:21 by mazaroua         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

void execute_command(t_cmd_line **cmd_line, t_env_list **env_list, int **fd, t_export **export)
{
	t_cmd_line *cmd_tmp = *cmd_line;
	int no_file = 1;
	t_redirections	*l_infile;
	t_redirections	*l_outfile;
	int i = 0;
	int flg = 0;
	pid_t	pid;
	int	heredoc_fd;
	while (cmd_tmp)
	{
		if (cmd_tmp->separator == e_pipe)
		{
			pipe(fd[i]);
			flg = 1;
		}
		ft_heredoc(&cmd_tmp, &heredoc_fd);
		if (!(pid = fork()))
		{
			l_infile = last_infile(&cmd_tmp, &no_file);
			if (!no_file)
				return ;
			l_outfile = last_outfile(&cmd_tmp);
			if (flg)
				dup_to_pipe(fd, i, count_list(cmd_line));
			if (l_outfile)
				dup_outfile(l_outfile);
			if (l_infile)
				dup_infile(l_infile);
			execute_command_2(&cmd_tmp, env_list,export);
		}
		close_pipes(fd , i, count_list(cmd_line), flg);
		cmd_tmp = cmd_tmp->next;
		i++;
	}
	while (wait(0) != -1);
}

void execution(t_cmd_line **cmd_line, t_env_list **env_list,t_export **export_list)
{
	if ((*cmd_line) && main_builtins(cmd_line) && (*cmd_line)->separator == e_nline) // main process // cd / unset / exit / export with variables
	{
		int	fd;
		ft_heredoc(cmd_line, &fd);
		execute_builtins(cmd_line, env_list,export_list);
	}
	else if ((*cmd_line))
	{
		int **fd = malloc(sizeof(int *) * count_list(cmd_line));
		int i = 0;
		while (i < count_list(cmd_line))
			fd[i++] = malloc(sizeof(int) * 2);
		execute_command(cmd_line, env_list, fd, export_list);
	}
}